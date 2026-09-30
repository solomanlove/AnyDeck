import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Finder 事件可能早于 Flutter 初始化，握手前保留所有路径。
  private var pendingApkPaths: [String] = []
  private var apkChannel: FlutterMethodChannel?
  private var apkReady = false
  private var lastQuitRequestTime: Date?
  private var windowChannel: FlutterMethodChannel?

  func configureWindowChannel(_ messenger: FlutterBinaryMessenger) {
    windowChannel = FlutterMethodChannel(name: "any_deck/window", binaryMessenger: messenger)
  }

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

  // FlutterAppDelegate 实现了 openURLs，AppKit 可能优先走此入口。
  override func application(_ application: NSApplication, open urls: [URL]) {
    let apkURLs = urls.filter { $0.isFileURL && $0.pathExtension.lowercased() == "apk" }
    receiveApkPaths(apkURLs.map { $0.path })
    let remaining = urls.filter { !($0.isFileURL && $0.pathExtension.lowercased() == "apk") }
    if !remaining.isEmpty {
      super.application(application, open: remaining)
    }
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    let paths = filenames.filter { URL(fileURLWithPath: $0).pathExtension.lowercased() == "apk" }
    receiveApkPaths(paths)
    sender.reply(toOpenOrPrint: paths.isEmpty ? .failure : .success)
  }

  private func receiveApkPaths(_ paths: [String]) {
    guard !paths.isEmpty else { return }
    if apkReady, let channel = apkChannel {
      channel.invokeMethod("openFiles", arguments: paths)
    } else {
      pendingApkPaths.append(contentsOf: paths)
    }
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

  // 收到退出请求时，2 秒内按两次直接退出；第一次拦截并通知 Flutter 弹出提示
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let now = Date()
    if let lastTime = lastQuitRequestTime, now.timeIntervalSince(lastTime) <= 2.0 {
      lastQuitRequestTime = nil
      return .terminateNow
    }
    lastQuitRequestTime = now

    if let channel = windowChannel {
      channel.invokeMethod("promptQuitConfirmation", arguments: nil)
    } else {
      for window in sender.windows {
        if let mainWindow = window as? MainFlutterWindow,
           let flutterVC = mainWindow.contentViewController as? FlutterViewController {
          let channel = FlutterMethodChannel(name: "any_deck/window", binaryMessenger: flutterVC.engine.binaryMessenger)
          channel.invokeMethod("promptQuitConfirmation", arguments: nil)
          break
        }
      }
    }
    return .terminateCancel
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
