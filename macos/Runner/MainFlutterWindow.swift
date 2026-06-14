import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  private var isChineseMode = true

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    let windowChannel = FlutterMethodChannel(
      name: "any_deck/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    windowChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "setWindowTitle" {
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
      } else if call.method == "setMenuLanguage" {
        guard let langCode = call.arguments as? String else {
          result(
            FlutterError(
              code: "invalid_argument",
              message: "setMenuLanguage requires a string languageCode",
              details: nil
            )
          )
          return
        }
        self?.isChineseMode = (langCode == "zh")
        if let title = self?.title {
          self?.syncSystemTitle(title)
        }
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    if let app = NSApplication.shared.delegate as? FlutterAppDelegate {
      app.mainFlutterWindow = self
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      
      let windowChannel = FlutterMethodChannel(
        name: "any_deck/window",
        binaryMessenger: controller.engine.binaryMessenger
      )
      
      var observers: [Any] = []
      var observersRegistered = false
      
      windowChannel.setMethodCallHandler { [weak controller, weak windowChannel] call, result in
        guard let window = controller?.view.window else {
          result(FlutterError(code: "no_window", message: "Window not found", details: nil))
          return
        }
        
        if !observersRegistered {
          observersRegistered = true
          
          let enterObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: window,
            queue: nil
          ) { [weak windowChannel] _ in
            windowChannel?.invokeMethod("onWindowEnterFullScreen", arguments: nil)
          }
          observers.append(enterObserver)
          
          let exitObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: window,
            queue: nil
          ) { [weak windowChannel] _ in
            windowChannel?.invokeMethod("onWindowLeaveFullScreen", arguments: nil)
          }
          observers.append(exitObserver)
          
          let closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: nil
          ) { _ in
            for observer in observers {
              NotificationCenter.default.removeObserver(observer)
            }
          }
          observers.append(closeObserver)
        }
        
        if call.method == "initWindow" {
          window.collectionBehavior.insert(.fullScreenPrimary)
          result(nil)
        } else if call.method == "setWindowTitle" {
          guard let title = call.arguments as? String else {
            result(FlutterError(code: "invalid_argument", message: "setWindowTitle requires a string title", details: nil))
            return
          }
          window.title = title
          result(nil)
        } else if call.method == "getWindowFrame" {
          let frame = window.frame
          let frameDict: [String: Any] = [
            "left": frame.origin.x,
            "top": frame.origin.y,
            "width": frame.size.width,
            "height": frame.size.height
          ]
          result(frameDict)
        } else if call.method == "setWindowFrame" {
          guard let args = call.arguments as? [String: Any],
                let left = args["left"] as? Double,
                let top = args["top"] as? Double,
                let width = args["width"] as? Double,
                let height = args["height"] as? Double else {
            result(FlutterError(code: "invalid_argument", message: "Requires left, top, width, height arguments", details: nil))
            return
          }
          window.setFrame(NSRect(x: left, y: top, width: width, height: height), display: true, animate: false)
          result(nil)
        } else if call.method == "setAlwaysOnTop" {
          guard let alwaysOnTop = call.arguments as? Bool else {
            result(FlutterError(code: "invalid_argument", message: "Requires bool arguments", details: nil))
            return
          }
          window.level = alwaysOnTop ? .floating : .normal
          result(nil)
        } else if call.method == "setFullScreen" {
          guard let fullscreen = call.arguments as? Bool else {
            result(FlutterError(code: "invalid_argument", message: "Requires bool arguments", details: nil))
            return
          }
          window.collectionBehavior.insert(.fullScreenPrimary)
          let isCurrentlyFullScreen = window.styleMask.contains(.fullScreen)
          if isCurrentlyFullScreen != fullscreen {
            window.toggleFullScreen(nil)
          }
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    super.awakeFromNib()
  }

  private func syncSystemTitle(_ title: String) {
    self.title = title

    guard let mainMenu = NSApp.mainMenu else {
      return
    }

    setupCustomWindowMenuItems()

    let isChinese = self.isChineseMode

    // 1. App Menu (first item)
    if mainMenu.items.count > 0 {
      let appMenuItem = mainMenu.items[0]
      appMenuItem.title = title
      if let submenu = appMenuItem.submenu {
        submenu.title = title
        
        // Update items in the Application Menu
        // About (index 0)
        if submenu.items.count > 0 {
          submenu.items[0].title = isChinese ? "关于 \(title)" : "About \(title)"
        }
        // Preferences (index 2)
        if submenu.items.count > 2 {
          submenu.items[2].title = isChinese ? "设置…" : "Preferences…"
        }
        // Services (index 4)
        if submenu.items.count > 4 {
          submenu.items[4].title = isChinese ? "服务" : "Services"
        }
        // Hide (index 6)
        if submenu.items.count > 6 {
          submenu.items[6].title = isChinese ? "隐藏 \(title)" : "Hide \(title)"
        }
        // Hide Others (index 7)
        if submenu.items.count > 7 {
          submenu.items[7].title = isChinese ? "隐藏其他" : "Hide Others"
        }
        // Show All (index 8)
        if submenu.items.count > 8 {
          submenu.items[8].title = isChinese ? "显示全部" : "Show All"
        }
        // Quit (index 10)
        if submenu.items.count > 10 {
          submenu.items[10].title = isChinese ? "退出 \(title)" : "Quit \(title)"
        }
      }
    }

    // 2. Edit Menu (second item)
    if mainMenu.items.count > 1 {
      let editMenuItem = mainMenu.items[1]
      editMenuItem.title = isChinese ? "编辑" : "Edit"
      if let submenu = editMenuItem.submenu {
        submenu.title = isChinese ? "编辑" : "Edit"
        // Undo (index 0)
        if submenu.items.count > 0 { submenu.items[0].title = isChinese ? "撤销" : "Undo" }
        // Redo (index 1)
        if submenu.items.count > 1 { submenu.items[1].title = isChinese ? "重做" : "Redo" }
        // Cut (index 3)
        if submenu.items.count > 3 { submenu.items[3].title = isChinese ? "剪切" : "Cut" }
        // Copy (index 4)
        if submenu.items.count > 4 { submenu.items[4].title = isChinese ? "复制" : "Copy" }
        // Paste (index 5)
        if submenu.items.count > 5 { submenu.items[5].title = isChinese ? "粘贴" : "Paste" }
        // Paste and Match Style (index 6)
        if submenu.items.count > 6 { submenu.items[6].title = isChinese ? "粘贴并匹配样式" : "Paste and Match Style" }
        // Delete (index 7)
        if submenu.items.count > 7 { submenu.items[7].title = isChinese ? "删除" : "Delete" }
        // Select All (index 8)
        if submenu.items.count > 8 { submenu.items[8].title = isChinese ? "全选" : "Select All" }
        
        // Find (index 10)
        if submenu.items.count > 10 {
          let findItem = submenu.items[10]
          findItem.title = isChinese ? "查找" : "Find"
          if let findSubmenu = findItem.submenu {
            findSubmenu.title = isChinese ? "查找" : "Find"
            if findSubmenu.items.count > 0 { findSubmenu.items[0].title = isChinese ? "查找…" : "Find…" }
            if findSubmenu.items.count > 1 { findSubmenu.items[1].title = isChinese ? "查找和替换…" : "Find and Replace…" }
            if findSubmenu.items.count > 2 { findSubmenu.items[2].title = isChinese ? "查找下一个" : "Find Next" }
            if findSubmenu.items.count > 3 { findSubmenu.items[3].title = isChinese ? "查找上一个" : "Find Previous" }
            if findSubmenu.items.count > 4 { findSubmenu.items[4].title = isChinese ? "使用所选内容查找" : "Use Selection for Find" }
            if findSubmenu.items.count > 5 { findSubmenu.items[5].title = isChinese ? "跳至所选内容" : "Jump to Selection" }
          }
        }
        
        // Spelling and Grammar (index 11)
        if submenu.items.count > 11 {
          let spellingItem = submenu.items[11]
          spellingItem.title = isChinese ? "拼写和语法" : "Spelling and Grammar"
          if let spellingSubmenu = spellingItem.submenu {
            spellingSubmenu.title = isChinese ? "拼写" : "Spelling"
            if spellingSubmenu.items.count > 0 { spellingSubmenu.items[0].title = isChinese ? "显示拼写和语法" : "Show Spelling and Grammar" }
            if spellingSubmenu.items.count > 1 { spellingSubmenu.items[1].title = isChinese ? "立即检查文稿" : "Check Document Now" }
            if spellingSubmenu.items.count > 3 { spellingSubmenu.items[3].title = isChinese ? "键入时检查拼写" : "Check Spelling While Typing" }
            if spellingSubmenu.items.count > 4 { spellingSubmenu.items[4].title = isChinese ? "检查拼写和语法" : "Check Grammar With Spelling" }
            if spellingSubmenu.items.count > 5 { spellingSubmenu.items[5].title = isChinese ? "自动纠正拼写" : "Correct Spelling Automatically" }
          }
        }
        
        // Substitutions (index 12)
        if submenu.items.count > 12 {
          let substitutionsItem = submenu.items[12]
          substitutionsItem.title = isChinese ? "替换" : "Substitutions"
          if let substitutionsSubmenu = substitutionsItem.submenu {
            substitutionsSubmenu.title = isChinese ? "替换" : "Substitutions"
            if substitutionsSubmenu.items.count > 0 { substitutionsSubmenu.items[0].title = isChinese ? "显示替换" : "Show Substitutions" }
            if substitutionsSubmenu.items.count > 2 { substitutionsSubmenu.items[2].title = isChinese ? "智能复制/粘贴" : "Smart Copy/Paste" }
            if substitutionsSubmenu.items.count > 3 { substitutionsSubmenu.items[3].title = isChinese ? "智能引号" : "Smart Quotes" }
            if substitutionsSubmenu.items.count > 4 { substitutionsSubmenu.items[4].title = isChinese ? "智能破折号" : "Smart Dashes" }
            if substitutionsSubmenu.items.count > 5 { substitutionsSubmenu.items[5].title = isChinese ? "智能链接" : "Smart Links" }
            if substitutionsSubmenu.items.count > 6 { substitutionsSubmenu.items[6].title = isChinese ? "数据检测器" : "Data Detectors" }
            if substitutionsSubmenu.items.count > 7 { substitutionsSubmenu.items[7].title = isChinese ? "文本替换" : "Text Replacement" }
          }
        }
        
        // Transformations (index 13)
        if submenu.items.count > 13 {
          let transformationsItem = submenu.items[13]
          transformationsItem.title = isChinese ? "转换" : "Transformations"
          if let transformationsSubmenu = transformationsItem.submenu {
            transformationsSubmenu.title = isChinese ? "转换" : "Transformations"
            if transformationsSubmenu.items.count > 0 { transformationsSubmenu.items[0].title = isChinese ? "变为大写" : "Make Upper Case" }
            if transformationsSubmenu.items.count > 1 { transformationsSubmenu.items[1].title = isChinese ? "变为小写" : "Make Lower Case" }
            if transformationsSubmenu.items.count > 2 { transformationsSubmenu.items[2].title = isChinese ? "首字母大写" : "Capitalize" }
          }
        }
        
        // Speech (index 14)
        if submenu.items.count > 14 {
          let speechItem = submenu.items[14]
          speechItem.title = isChinese ? "语音" : "Speech"
          if let speechSubmenu = speechItem.submenu {
            speechSubmenu.title = isChinese ? "语音" : "Speech"
            if speechSubmenu.items.count > 0 { speechSubmenu.items[0].title = isChinese ? "开始朗读" : "Start Speaking" }
            if speechSubmenu.items.count > 1 { speechSubmenu.items[1].title = isChinese ? "停止朗读" : "Stop Speaking" }
          }
        }
      }
    }

    // 3. View Menu (third item)
    if mainMenu.items.count > 2 {
      let viewMenuItem = mainMenu.items[2]
      viewMenuItem.title = isChinese ? "显示" : "View"
      if let submenu = viewMenuItem.submenu {
        submenu.title = isChinese ? "显示" : "View"
        if submenu.items.count > 0 { submenu.items[0].title = isChinese ? "进入全屏幕" : "Enter Full Screen" }
      }
    }

    // 4. Window Menu (fourth item)
    if mainMenu.items.count > 3 {
      let windowMenuItem = mainMenu.items[3]
      windowMenuItem.title = isChinese ? "窗口" : "Window"
      if let submenu = windowMenuItem.submenu {
        submenu.title = isChinese ? "窗口" : "Window"
        if submenu.items.count > 0 { submenu.items[0].title = isChinese ? "最小化" : "Minimize" }
        if submenu.items.count > 1 { submenu.items[1].title = isChinese ? "缩放" : "Zoom" }
        if submenu.items.count > 3 { submenu.items[3].title = isChinese ? "前置全部窗口" : "Bring All to Front" }
        
        for item in submenu.items {
          if item.action == #selector(openEmulatorManagerClicked(_:)) {
            item.title = isChinese ? "模拟器管理窗口" : "Simulator Management Window"
          } else if item.action == #selector(openMirrorWindowClicked(_:)) {
            item.title = isChinese ? "投屏窗口" : "Screen Casting Window"
          }
        }
      }
    }

    // 5. Help Menu (fifth item)
    if mainMenu.items.count > 4 {
      let helpMenuItem = mainMenu.items[4]
      helpMenuItem.title = isChinese ? "帮助" : "Help"
      if let submenu = helpMenuItem.submenu {
        submenu.title = isChinese ? "帮助" : "Help"
      }
    }
  }

  @objc func openEmulatorManagerClicked(_ sender: Any) {
    if let controller = self.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "any_deck/window",
        binaryMessenger: controller.engine.binaryMessenger
      )
      channel.invokeMethod("openEmulatorManager", arguments: nil)
    }
  }

  @objc func openMirrorWindowClicked(_ sender: Any) {
    if let controller = self.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "any_deck/window",
        binaryMessenger: controller.engine.binaryMessenger
      )
      channel.invokeMethod("openMirrorWindow", arguments: nil)
    }
  }

  private func setupCustomWindowMenuItems() {
    guard let mainMenu = NSApp.mainMenu, mainMenu.items.count > 3,
          let submenu = mainMenu.items[3].submenu else {
      return
    }
    
    let hasCustomItems = submenu.items.contains { item in
      item.action == #selector(openEmulatorManagerClicked(_:)) ||
      item.action == #selector(openMirrorWindowClicked(_:))
    }
    
    if !hasCustomItems {
      submenu.addItem(NSMenuItem.separator())
      
      let emulatorItem = NSMenuItem(
        title: "模拟器管理窗口",
        action: #selector(openEmulatorManagerClicked(_:)),
        keyEquivalent: ""
      )
      emulatorItem.target = self
      submenu.addItem(emulatorItem)
      
      let mirrorItem = NSMenuItem(
        title: "投屏窗口",
        action: #selector(openMirrorWindowClicked(_:)),
        keyEquivalent: ""
      )
      mirrorItem.target = self
      submenu.addItem(mirrorItem)
    }
  }
}
