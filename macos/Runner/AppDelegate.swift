import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
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

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    var hasMainWindow = false
    for window in sender.windows {
      if let mainWin = window as? MainFlutterWindow {
        hasMainWindow = true
        if !mainWin.isVisible {
          mainWin.makeKeyAndOrderFront(nil)
          NSApp.activate(ignoringOtherApps: true)
        } else {
          mainWin.makeKeyAndOrderFront(nil)
        }
        
        if let controller = mainWin.contentViewController as? FlutterViewController {
          let channel = FlutterMethodChannel(
            name: "adb_manage/window",
            binaryMessenger: controller.engine.binaryMessenger
          )
          channel.invokeMethod("requestAppExit", arguments: nil)
        }
      }
    }
    if hasMainWindow {
      return .terminateCancel
    }
    return .terminateNow
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
