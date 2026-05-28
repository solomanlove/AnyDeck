import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    let windowChannel = FlutterMethodChannel(
      name: "adb_manage/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    windowChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setWindowTitle" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let title = call.arguments as? String else {
        result(
          FlutterError(
            code: "invalid_argument",
            message: "setWindowTitle requires a string title",
            details: nil
          )
        )
        return
      }
      self?.syncSystemTitle(title)
      result(nil)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  private func syncSystemTitle(_ title: String) {
    self.title = title

    guard let appMenuItem = NSApp.mainMenu?.items.first else {
      return
    }

    appMenuItem.title = title
    appMenuItem.submenu?.title = title
  }
}
