import Cocoa

/// 菜单栏是关闭配置弹窗后的切镜头/停止入口，文案由 Flutter 本地化传入。
final class VirtualCameraMenu: NSObject {
  private var item: NSStatusItem?
  var selectFront: ((Bool) -> Void)?
  var stop: (() -> Void)?
  func update(enabled: Bool, front: Bool, labels: [String: String]) {
    guard enabled else {
      if let item { NSStatusBar.system.removeStatusItem(item) }
      item = nil; return
    }
    if item == nil { item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) }
    item?.button?.image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: labels["title"])
    item?.button?.toolTip = labels["title"] ?? "AnyDeck Camera"
    let menu = NSMenu()
    for (key, value) in [("back", false), ("front", true)] {
      let choice = NSMenuItem(title: labels[key] ?? key, action: #selector(lens(_:)), keyEquivalent: "")
      choice.target = self; choice.tag = value ? 1 : 0; choice.state = front == value ? .on : .off
      menu.addItem(choice)
    }
    menu.addItem(.separator())
    let off = NSMenuItem(title: labels["stop"] ?? "Stop", action: #selector(disable), keyEquivalent: "")
    off.target = self; menu.addItem(off); item?.menu = menu
  }
  @objc private func lens(_ sender: NSMenuItem) { selectFront?(sender.tag == 1) }
  @objc private func disable() { stop?() }
}
