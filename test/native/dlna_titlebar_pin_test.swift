import Cocoa

/// 验证原生标题栏使用同源的两种矢量图标，切换状态不丢失 Tooltip 或点击回调。
@main
struct DlnaTitlebarPinTest {
  static func main() {
    _ = NSApplication.shared
    let catalog = URL(fileURLWithPath: CommandLine.arguments[1])
    for name in ["DlnaPin", "DlnaPinFilled"] {
      let url = catalog.appendingPathComponent("\(name).imageset/\(name).pdf")
      let image = NSImage(contentsOf: url)!
      precondition(image.size == NSSize(width: 16, height: 16))
      precondition(image.representations.first is NSPDFImageRep)
      precondition(image.setName(name))
    }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
                          styleMask: [.titled], backing: .buffered, defer: false)
    var taps = 0
    let control = DlnaTitlebarPinControl.install(on: window) { taps += 1 }
    let button = window.titlebarAccessoryViewControllers.last!.view as! NSButton
    for pinned in [false, true, false] {
      control.update(pinned: pinned, pinLabel: "置顶窗口", unpinLabel: "取消置顶")
      precondition(button.image === NSImage(named: pinned ? "DlnaPinFilled" : "DlnaPin"))
      precondition(button.image?.isTemplate == true)
      precondition(button.toolTip == (pinned ? "取消置顶" : "置顶窗口"))
      precondition(button.contentTintColor == (pinned ? .systemOrange : .secondaryLabelColor))
    }
    button.performClick(nil)
    precondition(taps == 1)
    print("DLNA Cupertino pin icons: passed")
  }
}
