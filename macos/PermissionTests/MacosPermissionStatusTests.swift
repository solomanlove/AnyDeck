import AVFoundation
import CoreBluetooth
import CoreLocation
import Foundation
import ServiceManagement
import UserNotifications

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
    precondition(MacosPermissionStatus.camera(.authorized) == "authorized")
    precondition(MacosPermissionStatus.camera(.notDetermined) == "notDetermined")
    precondition(MacosPermissionStatus.camera(.denied) == "denied")
    precondition(MacosPermissionStatus.camera(.restricted) == "restricted")
    precondition(MacosPermissionStatus.bluetooth(.allowedAlways) == "authorized")
    precondition(MacosPermissionStatus.bluetooth(.notDetermined) == "notDetermined")
    precondition(MacosPermissionStatus.bluetooth(.denied) == "denied")
    precondition(MacosPermissionStatus.bluetooth(.restricted) == "restricted")
    precondition(MacosPermissionStatus.location(.authorizedAlways, servicesEnabled: false) == "disabled")
    precondition(MacosPermissionStatus.location(.authorizedAlways, servicesEnabled: true) == "authorized")
    precondition(MacosPermissionStatus.location(.notDetermined, servicesEnabled: true) == "notDetermined")
    precondition(MacosPermissionStatus.location(.denied, servicesEnabled: true) == "denied")
    precondition(MacosPermissionStatus.location(.restricted, servicesEnabled: true) == "restricted")
    precondition(MacosPermissionStatus.notifications(.provisional) == "authorized")
    precondition(MacosPermissionStatus.notifications(.notDetermined) == "notDetermined")
    precondition(MacosPermissionStatus.notifications(.denied) == "denied")
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
    for invalid in ["", "files?Privacy_AllFiles", "camera\n", "https://example.com", "../camera"] {
      precondition(MacosPermissionStatus.settingsURL(for: invalid) == nil)
      precondition(!MacosPermissionStatus.requestable.contains(invalid))
    }
    precondition(MacosPermissionStatus.requestable == ["camera", "bluetooth", "location", "notifications"])
    precondition(!MacosPermissionStatus.requestable.contains("cameraExtension"))
    precondition(!MacosPermissionStatus.requestable.contains("localNetwork"))
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
    let snapshot = MacosPermissionSnapshot(values: ["camera": "authorized", "notifications": "unknown"],
      pending: ["notifications", "cameraExtension"]) { results.append($0) }
    snapshot.update("notifications", status: "denied")
    snapshot.update("notifications", status: "authorized")
    precondition(results.isEmpty, "重复回调不得提前完成另一项查询")
    snapshot.finish()
    snapshot.update("cameraExtension", status: "authorized")
    snapshot.finish()
    precondition(results == [["camera": "authorized", "notifications": "denied"]],
      "超时后迟到回调不得二次返回或覆盖快照")
    let complete = MacosPermissionSnapshot(values: ["notifications": "unknown"], pending: ["notifications"]) {
      results.append($0)
    }
    complete.update("notifications", status: "authorized")
    complete.finish()
    precondition(results.count == 2 && results.last?["notifications"] == "authorized")
  }
}
