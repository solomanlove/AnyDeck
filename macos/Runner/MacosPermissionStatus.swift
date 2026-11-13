import AVFoundation
import CoreBluetooth
import CoreLocation
import Foundation
import ServiceManagement
import UserNotifications

/// 系统权限状态与设置入口的纯映射；不会请求权限、读取文件或启动硬件。
enum MacosPermissionStatus {
  static let permissions = ["camera", "bluetooth", "location", "notifications",
                            "cameraExtension", "loginItems"]
  static let requestable: Set<String> = ["camera", "bluetooth", "location", "notifications"]

  static func camera(_ status: AVAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "authorized"
    case .notDetermined: return "notDetermined"
    case .denied: return "denied"
    case .restricted: return "restricted"
    @unknown default: return "unknown"
    }
  }

  static func bluetooth(_ status: CBManagerAuthorization) -> String {
    switch status {
    case .allowedAlways: return "authorized"
    case .notDetermined: return "notDetermined"
    case .denied: return "denied"
    case .restricted: return "restricted"
    @unknown default: return "unknown"
    }
  }

  static func location(_ status: CLAuthorizationStatus, servicesEnabled: Bool) -> String {
    guard servicesEnabled else { return "disabled" }
    switch status {
    case .authorizedAlways: return "authorized"
    case .notDetermined: return "notDetermined"
    case .denied: return "denied"
    case .restricted: return "restricted"
    @unknown default: return "unknown"
    }
  }

  static func notifications(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .authorized, .provisional: return "authorized"
    case .notDetermined: return "notDetermined"
    case .denied: return "denied"
    @unknown default: return "unknown"
    }
  }

  @available(macOS 13.0, *)
  static func loginItems(_ status: SMAppService.Status) -> String {
    switch status {
    case .enabled: return "authorized"
    case .notRegistered: return "disabled"
    case .requiresApproval: return "denied"
    case .notFound: return "unsupported"
    @unknown default: return "unknown"
    }
  }

  static func cameraExtension(supported: Bool, installEntitlement: Bool,
                              installed: Bool, activation: String) -> String {
    guard supported && installEntitlement else { return "unsupported" }
    if activation == "needsReboot" { return "manual" }
    if activation == "needsApproval" { return "denied" }
    if installed { return "authorized" }
    // 激活错误或未发现设备无法证明系统已拒绝，交由用户在设置中确认。
    return "manual"
  }

  static func settingsURL(for permission: String) -> URL? {
    let suffix: String
    switch permission {
    case "camera": suffix = "com.apple.preference.security?Privacy_Camera"
    case "bluetooth": suffix = "com.apple.preference.security?Privacy_Bluetooth"
    case "location": suffix = "com.apple.preference.security?Privacy_LocationServices"
    case "notifications": suffix = "com.apple.preference.notifications"
    case "cameraExtension":
      // macOS 15 起扩展迁移到登录项与扩展，旧版仍在隐私与安全性批准。
      if #available(macOS 15.0, *) { suffix = "com.apple.LoginItems-Settings.extension" }
      else { suffix = "com.apple.preference.security" }
    case "loginItems":
      if #available(macOS 13.0, *) { suffix = "com.apple.LoginItems-Settings.extension" }
      else { suffix = "com.apple.preference.users" }
    default: return nil
    }
    return URL(string: "x-apple.systempreferences:\(suffix)")
  }
}

/// 聚合只读异步结果；超时和迟到回调共用一次性完成边界，避免重复回复 Flutter。
final class MacosPermissionSnapshot {
  private var values: [String: String]
  private var pending: Set<String>
  private var completion: (([String: String]) -> Void)?

  init(values: [String: String], pending: Set<String>,
       completion: @escaping ([String: String]) -> Void) {
    self.values = values
    self.pending = pending
    self.completion = completion
  }

  func update(_ permission: String, status: String) {
    guard completion != nil, pending.remove(permission) != nil else { return }
    values[permission] = status
    if pending.isEmpty { finish() }
  }

  func finish() {
    guard let completion else { return }
    self.completion = nil
    completion(values)
  }
}
