import Cocoa
import FlutterMacOS
import ServiceManagement

/// 主 Engine 的手动批准入口；只读系统状态，不申请权限或启用功能。
final class MacosPermissionBridgeService: NSObject {
  static let shared = MacosPermissionBridgeService()

  func setup(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "anydeck/macos_permissions", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "permission_unavailable", message: nil, details: nil))
        return
      }
      switch call.method {
      case "readAll": self.readAll(result)
      case "openSettings":
        guard let arguments = call.arguments as? [String: Any],
              let permission = arguments["permission"] as? String,
              MacosPermissionStatus.permissions.contains(permission) else {
          result(FlutterError(code: "invalid_argument", message: "Unknown macOS permission", details: nil))
          return
        }
        self.openSettings(permission, result: result)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func readAll(_ result: @escaping FlutterResult) {
    var values = Dictionary(uniqueKeysWithValues: MacosPermissionStatus.permissions.map { ($0, "unknown") })
    if #available(macOS 13.0, *) {
      values["loginItems"] = MacosPermissionStatus.loginItems(SMAppService.mainApp.status)
    } else { values["loginItems"] = "manual" }
    let snapshot = MacosPermissionSnapshot(values: values, pending: ["cameraExtension"]) {
      result($0)
    }
    // 单项查询迟到也不阻塞整个页面，未返回项保留 unknown。
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { snapshot.finish() }
    VirtualCameraPlugin.readPermissionStatus { snapshot.update("cameraExtension", status: $0) }
  }

  private func openSettings(_ permission: String, result: FlutterResult) {
    guard let url = MacosPermissionStatus.settingsURL(for: permission) else {
      result(FlutterError(code: "invalid_argument", message: "Unknown macOS permission", details: nil))
      return
    }
    guard NSWorkspace.shared.open(url) else {
      result(FlutterError(code: "settings_open_failed", message: nil, details: nil))
      return
    }
    result(nil)
  }
}
