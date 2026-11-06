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

  private static func isAndroidPackage(_ url: URL) -> Bool {
    return url.isFileURL && ["apk", "apks", "aab", "xapk"].contains(url.pathExtension.lowercased())
  }

  // FlutterAppDelegate 实现了 openURLs，AppKit 可能优先走此入口。
  override func application(_ application: NSApplication, open urls: [URL]) {
    let apkURLs = urls.filter { Self.isAndroidPackage($0) }
    receiveApkPaths(apkURLs.map { $0.path })
    let remaining = urls.filter { !(Self.isAndroidPackage($0)) }
    if !remaining.isEmpty {
      super.application(application, open: remaining)
    }
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    let paths = filenames.filter { Self.isAndroidPackage(URL(fileURLWithPath: $0)) }
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

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
