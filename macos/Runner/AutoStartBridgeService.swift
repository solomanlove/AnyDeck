import Cocoa
import FlutterMacOS
import ServiceManagement

/// macOS 开机自启桥接服务，负责与系统登录项及 LaunchAgents 交互。
class AutoStartBridgeService: NSObject {
  static let shared = AutoStartBridgeService()

  private let plistLabel = "com.github.anydeck"

  private var launchAgentFile: URL? {
    guard let libDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
      return nil
    }
    return libDir.appendingPathComponent("LaunchAgents").appendingPathComponent("\(plistLabel).plist")
  }

  /// 在主 Flutter Engine 上注册原生自启通道。
  func setup(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "any_deck/autostart", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(false)
        return
      }
      switch call.method {
      case "isEnabled":
        result(self.isAutoStartEnabled())
      case "status":
        result(self.authorizationStatus())
      case "openSettings":
        guard let url = Self.settingsURL, NSWorkspace.shared.open(url) else {
          result(FlutterError(code: "settings_open_failed", message: nil, details: nil))
          return
        }
        result(nil)
      case "setEnabled":
        guard let enabled = call.arguments as? Bool else {
          result(FlutterError(code: "invalid_argument", message: "Boolean argument required", details: nil))
          return
        }
        result(self.setAutoStartEnabled(enabled))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 新系统只信任实际启用状态；旧系统保留原 LaunchAgent 配置查询。
  func isAutoStartEnabled() -> Bool {
    if #available(macOS 13.0, *) {
      return SMAppService.mainApp.status == .enabled
    }
    if let fileUrl = launchAgentFile {
      return FileManager.default.fileExists(atPath: fileUrl.path)
    }
    return false
  }

  /// 只读查询不注册登录项；旧系统配置存在不等于系统已允许运行。
  func authorizationStatus() -> String {
    if #available(macOS 13.0, *) {
      return Self.statusName(SMAppService.mainApp.status, legacyConfigured: legacyConfigurationExists)
    }
    return isAutoStartEnabled() ? "manual" : "disabled"
  }

  @available(macOS 13.0, *)
  static func statusName(_ status: SMAppService.Status, legacyConfigured: Bool = false) -> String {
    switch status {
    case .enabled: return "enabled"
    case .notRegistered: return legacyConfigured ? "manual" : "disabled"
    case .requiresApproval: return "requiresApproval"
    case .notFound: return "unavailable"
    @unknown default: return "unknown"
    }
  }

  private var legacyConfigurationExists: Bool {
    guard let fileUrl = launchAgentFile else { return false }
    return FileManager.default.fileExists(atPath: fileUrl.path)
  }

  static var settingsURL: URL? {
    if #available(macOS 13.0, *) {
      return URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }
    return URL(string: "x-apple.systempreferences:com.apple.preference.users")
  }

  /// 注册成功仍可能待批准；新系统失败时不写 LaunchAgent 绕过系统状态。
  func setAutoStartEnabled(_ enabled: Bool) -> Bool {
    if #available(macOS 13.0, *) {
      do {
        if enabled {
          if SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval {
            try SMAppService.mainApp.register()
          }
        } else {
          if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
          }
        }
        if let fileUrl = launchAgentFile, FileManager.default.fileExists(atPath: fileUrl.path) {
          try FileManager.default.removeItem(at: fileUrl)
        }
        return true
      } catch {
        NSLog("[AutoStartBridgeService] Failed to update login item")
        return false
      }
    }
    return setLaunchAgentEnabled(enabled)
  }

  /// 使用 LaunchAgent 方式控制自启。
  private func setLaunchAgentEnabled(_ enabled: Bool) -> Bool {
    guard let fileUrl = launchAgentFile else { return false }
    let fileManager = FileManager.default
    if enabled {
      do {
        let dir = fileUrl.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
          try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        let bundlePath = Bundle.main.bundlePath
        let plistContent: [String: Any] = [
          "Label": plistLabel,
          "ProgramArguments": ["/usr/bin/open", "-a", bundlePath],
          "RunAtLoad": true,
          "ProcessType": "Interactive"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plistContent, format: .xml, options: 0)
        try data.write(to: fileUrl, options: .atomic)
        return true
      } catch {
        NSLog("[AutoStartBridgeService] Failed to write LaunchAgent plist: \(error)")
        return false
      }
    } else {
      do {
        if fileManager.fileExists(atPath: fileUrl.path) {
          try fileManager.removeItem(at: fileUrl)
        }
        return true
      } catch {
        NSLog("[AutoStartBridgeService] Failed to delete LaunchAgent plist: \(error)")
        return false
      }
    }
  }
}
