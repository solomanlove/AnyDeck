import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Finder 事件可能早于 Flutter 初始化，握手前保留所有路径。
  private var pendingApkPaths: [String] = []
  private var apkChannel: FlutterMethodChannel?
  private var apkReady = false

  func configureApkChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "any_deck/apk_files", binaryMessenger: messenger)
    apkChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      if call.method == "ready" {
        self.apkReady = true
        let paths = self.pendingApkPaths
        self.pendingApkPaths.removeAll()
        result(paths)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    let paths = filenames.filter { URL(fileURLWithPath: $0).pathExtension.lowercased() == "apk" }
    if apkReady, let channel = apkChannel {
      channel.invokeMethod("openFiles", arguments: paths)
    } else {
      pendingApkPaths.append(contentsOf: paths)
    }
    sender.reply(toOpenOrPrint: paths.isEmpty ? .failure : .success)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows {
        if window is MainFlutterWindow {
          window.makeKeyAndOrderFront(nil)
          NSApp.activate(ignoringOtherApps: true)
          break
        }
      }
    }
    return true
  }

  // 真正收到退出请求时直接退出；Command+Q 的双按确认由 Flutter 主窗口处理。
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    return .terminateNow
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
