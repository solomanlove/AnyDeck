import Foundation
import ServiceManagement

/// 离线测试纯状态映射及异步完成边界，不查询 TCC、不启动 App 或显示授权弹窗。
@main
struct MacosPermissionStatusTests {
  static func main() {
    checkAuthorizationMappings()
    checkSettingsWhitelist()
    checkExtensionBoundaries()
    checkSnapshotCompletion()
    print("MacosPermissionStatusTests: 4 groups passed")
  }

  private static func checkAuthorizationMappings() {
    if #available(macOS 13.0, *) {
      precondition(MacosPermissionStatus.loginItems(.enabled) == "authorized")
      precondition(MacosPermissionStatus.loginItems(.notRegistered) == "disabled")
      precondition(MacosPermissionStatus.loginItems(.requiresApproval) == "denied")
      precondition(MacosPermissionStatus.loginItems(.notFound) == "unsupported")
    }
  }

  private static func checkSettingsWhitelist() {
    for permission in MacosPermissionStatus.permissions {
      precondition(MacosPermissionStatus.settingsURL(for: permission)?.scheme == "x-apple.systempreferences")
    }
    for invalid in ["", "camera", "bluetooth", "location", "notifications", "localNetwork", "files",
                    "files?Privacy_AllFiles", "camera\n", "https://example.com", "../camera"] {
      precondition(MacosPermissionStatus.settingsURL(for: invalid) == nil)
      precondition(!MacosPermissionStatus.permissions.contains(invalid))
    }
    precondition(Set(MacosPermissionStatus.permissions) == ["cameraExtension", "loginItems"])
    let extensionURL = MacosPermissionStatus.settingsURL(for: "cameraExtension")?.absoluteString
    if #available(macOS 15.0, *) {
      precondition(extensionURL == "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    } else {
      precondition(extensionURL == "x-apple.systempreferences:com.apple.preference.security")
    }
    let loginURL = MacosPermissionStatus.settingsURL(for: "loginItems")?.absoluteString
    if #available(macOS 13.0, *) {
      precondition(loginURL == "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    } else {
      precondition(loginURL == "x-apple.systempreferences:com.apple.preference.users")
    }
  }

  private static func checkExtensionBoundaries() {
    precondition(MacosPermissionStatus.cameraExtension(supported: true, installEntitlement: false,
      installed: true, activation: "ready") == "unsupported", "普通签名构建不得误报扩展可用")
    precondition(MacosPermissionStatus.cameraExtension(supported: false, installEntitlement: true,
      installed: true, activation: "ready") == "unsupported")
    precondition(MacosPermissionStatus.cameraExtension(supported: true, installEntitlement: true,
      installed: true, activation: "needsReboot") == "manual", "旧设备可见不能覆盖待重启状态")
    precondition(MacosPermissionStatus.cameraExtension(supported: true, installEntitlement: true,
      installed: false, activation: "needsApproval") == "denied")
    precondition(MacosPermissionStatus.cameraExtension(supported: true, installEntitlement: true,
      installed: true, activation: "notInstalled") == "authorized")
    precondition(MacosPermissionStatus.cameraExtension(supported: true, installEntitlement: true,
      installed: false, activation: "error") == "manual", "激活错误不代表用户拒绝")
  }

  private static func checkSnapshotCompletion() {
    var results: [[String: String]] = []
    let snapshot = MacosPermissionSnapshot(values: ["loginItems": "authorized", "cameraExtension": "unknown"],
      pending: ["cameraExtension"]) { results.append($0) }
    snapshot.update("camera", status: "authorized")
    precondition(results.isEmpty, "非待查询项不得改变权限快照")
    snapshot.finish()
    snapshot.update("cameraExtension", status: "authorized")
    snapshot.finish()
    precondition(results == [["loginItems": "authorized", "cameraExtension": "unknown"]],
      "超时后迟到回调不得二次返回或覆盖快照")
    let complete = MacosPermissionSnapshot(values: ["cameraExtension": "unknown"], pending: ["cameraExtension"]) {
      results.append($0)
    }
    complete.update("cameraExtension", status: "denied")
    complete.update("cameraExtension", status: "authorized")
    complete.finish()
    precondition(results.count == 2 && results.last?["cameraExtension"] == "denied", "完成后重复回调不得改变结果")
  }
}
