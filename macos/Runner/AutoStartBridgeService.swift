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

  /// 检查当前是否开启了自启（优先检查 SMAppService，未开启时检查 LaunchAgents）。
  func isAutoStartEnabled() -> Bool {
    if #available(macOS 13.0, *) {
      let status = SMAppService.mainApp.status
      if status == .enabled {
        return true
      }
    }
    if let fileUrl = launchAgentFile {
      return FileManager.default.fileExists(atPath: fileUrl.path)
    }
    return false
  }

  /// 设置自启动状态。优先采用 macOS 13+ 官方推荐的 SMAppService，失败时自动降级使用 LaunchAgent plist。
  func setAutoStartEnabled(_ enabled: Bool) -> Bool {
    var smSuccess = false
    if #available(macOS 13.0, *) {
      do {
        if enabled {
          if SMAppService.mainApp.status != .enabled {
            try SMAppService.mainApp.register()
          }
        } else {
          if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
          }
        }
        smSuccess = true
      } catch {
        NSLog("[AutoStartBridgeService] SMAppService call failed: \(error)")
        smSuccess = false
      }
    }

    if smSuccess {
      // 若使用 SMAppService 成功，且为禁用操作，清理可能遗留的历史 LaunchAgent 文件
      if !enabled, let fileUrl = launchAgentFile, FileManager.default.fileExists(atPath: fileUrl.path) {
        try? FileManager.default.removeItem(at: fileUrl)
      }
      return true
    }

    // 降级方案：管理 ~/Library/LaunchAgents/com.github.anydeck.plist
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
