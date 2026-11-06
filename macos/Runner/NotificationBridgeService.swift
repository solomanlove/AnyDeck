import Cocoa
import FlutterMacOS
import UserNotifications

/// macOS 原生本地通知桥接服务，负责与 UNUserNotificationCenter 交互并分发点击事件。
@available(macOS 10.14, *)
class NotificationBridgeService: NSObject, UNUserNotificationCenterDelegate {
  static let shared = NotificationBridgeService()

  private var channel: FlutterMethodChannel?
  private var isFlutterReady = false
  private var pendingClicks: [[String: Any]] = []
  private static let incomingCategory = "harmony_share_incoming"
  private static let acceptAction = "harmony_share_accept"
  private static let rejectAction = "harmony_share_reject"

  /// 仅在主 Flutter Engine 初始化时注册通道。
  func setup(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "any_deck/notifications", binaryMessenger: messenger)
    self.channel = channel
    UNUserNotificationCenter.current().delegate = self

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "requestAuthorization":
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
          DispatchQueue.main.async {
            // 系统调用失败不等同用户拒绝，让交互界面保留错误并提供设置入口。
            if let error = error {
              result(FlutterError(code: "authorization_failed", message: error.localizedDescription, details: nil))
              return
            }
            result(granted)
          }
        }
      case "getAuthorizationStatus":
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          DispatchQueue.main.async {
            let status: String
            switch settings.authorizationStatus {
            case .authorized:
              status = "authorized"
            case .denied:
              status = "denied"
            case .notDetermined:
              status = "notDetermined"
            case .provisional:
              status = "provisional"
            @unknown default:
              status = "unknown"
            }
            result(status)
          }
        }
      case "showIncomingFileOffer":
        self.showIncomingFileOffer(arguments: call.arguments, result: result)
      case "showNotification":
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? String,
              let title = args["title"] as? String else {
          result(FlutterError(code: "invalid_args", message: "id and title required", details: nil))
          return
        }
        let body = args["body"] as? String ?? ""
        let payload = args["payload"] as? [String: Any] ?? [:]

        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = args["subtitle"] as? String ?? ""
        content.body = body
        content.sound = UNNotificationSound.default
        content.userInfo = payload

        // 通知附件使用缓存图标的临时副本，避免系统接收附件时移动原始缓存文件。
        let iconAttachment = self.makeIconAttachment(path: args["iconPath"] as? String)
        if let attachment = iconAttachment.attachment {
          content.attachments = [attachment]
        }

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
          if let temporaryURL = iconAttachment.temporaryURL {
            try? FileManager.default.removeItem(at: temporaryURL)
          }
          DispatchQueue.main.async {
            if let error = error {
              result(FlutterError(code: "add_failed", message: error.localizedDescription, details: nil))
            } else {
              result(true)
            }
          }
        }
      case "removeNotification":
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? String else {
          result(nil)
          return
        }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        result(true)
      case "removeAllNotifications":
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        result(true)
      case "removeNotificationsWithPrefix":
        guard let args = call.arguments as? [String: Any],
              let prefix = args["prefix"] as? String else {
          result(nil)
          return
        }
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notifications in
          let identifiers = notifications
            .map { $0.request.identifier }
            .filter { $0.hasPrefix(prefix) }
          center.removeDeliveredNotifications(withIdentifiers: identifiers)
          center.getPendingNotificationRequests { requests in
            let pendingIdentifiers = requests
              .map { $0.identifier }
              .filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers)
            DispatchQueue.main.async {
              result(true)
            }
          }
        }
      case "openNotificationSettings":
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
          NSWorkspace.shared.open(url)
        }
        result(true)
      case "ready":
        self.isFlutterReady = true
        let clicks = self.pendingClicks
        self.pendingClicks.removeAll()
        result(clicks)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 先登记当前语言的固定类别，再提交来件；不申请权限，也不写入文件名或本地路径。
  private func showIncomingFileOffer(arguments: Any?, result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any],
          let id = args["id"] as? String, !id.isEmpty,
          let title = args["title"] as? String, !title.isEmpty,
          let body = args["body"] as? String,
          let acceptLabel = args["acceptLabel"] as? String, !acceptLabel.isEmpty,
          let rejectLabel = args["rejectLabel"] as? String, !rejectLabel.isEmpty,
          let payload = args["payload"] as? [String: Any],
          payload["type"] as? String == "harmony_share_offer",
          let token = payload["offerToken"] as? String, !token.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Valid incoming offer and action labels required", details: nil))
      return
    }
    let center = UNUserNotificationCenter.current()
    let category = UNNotificationCategory(
      identifier: Self.incomingCategory,
      actions: [
        UNNotificationAction(identifier: Self.acceptAction, title: acceptLabel, options: [.authenticationRequired]),
        UNNotificationAction(identifier: Self.rejectAction, title: rejectLabel, options: [])
      ],
      intentIdentifiers: [],
      options: [.customDismissAction]
    )
    center.getNotificationCategories { existing in
      // 使用固定类别避免随请求累积，并保留其他功能登记的类别。
      var categories = existing.filter { $0.identifier != Self.incomingCategory }
      categories.insert(category)
      center.setNotificationCategories(categories)
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      content.categoryIdentifier = Self.incomingCategory
      content.userInfo = payload
      let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
      center.add(request) { error in
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(code: "add_failed", message: error.localizedDescription, details: nil))
          } else {
            result(true)
          }
        }
      }
    }
  }

  /// 仅复制有效的本地图标；无图标或附件创建失败时继续发送普通文字通知。
  private func makeIconAttachment(path: String?) -> (attachment: UNNotificationAttachment?, temporaryURL: URL?) {
    guard let path = path, !path.isEmpty else { return (nil, nil) }
    let sourceURL = URL(fileURLWithPath: path)
    guard sourceURL.pathExtension.lowercased() == "png",
          let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
          let fileSize = attributes[.size] as? NSNumber,
          fileSize.intValue > 0 && fileSize.intValue <= 10 * 1024 * 1024 else {
      return (nil, nil)
    }

    let temporaryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("anydeck-notification-\(UUID().uuidString).png")
    do {
      try FileManager.default.copyItem(at: sourceURL, to: temporaryURL)
      let attachment = try UNNotificationAttachment(identifier: "phone_app_icon", url: temporaryURL, options: nil)
      return (attachment, temporaryURL)
    } catch {
      try? FileManager.default.removeItem(at: temporaryURL)
      return (nil, nil)
    }
  }

  // 应用在前台运行时依然展示通知横幅
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(macOS 11.0, *) {
      completionHandler([.banner, .sound, .list])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  // 用户点击通知横幅后的回调响应
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let interaction = Self.notificationInteraction(
      request: response.notification.request, actionIdentifier: response.actionIdentifier
    )

    DispatchQueue.main.async {
      // 正文点击打开主窗口；通知按钮直接决定来件，不抢占用户当前窗口焦点。
      if interaction.focusWindow {
        for window in NSApp.windows {
          if window is MainFlutterWindow {
            if window.isMiniaturized {
              window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            break
          }
        }
      }

      if self.isFlutterReady, let channel = self.channel {
        channel.invokeMethod("onNotificationClicked", arguments: interaction.payload)
      } else {
        self.pendingClicks.append(interaction.payload)
      }
      completionHandler()
    }
  }

  /// 只从系统类别及 actionIdentifier 生成可信动作；普通通知不能通过 payload 冒充接收操作。
  static func notificationInteraction(
    request: UNNotificationRequest, actionIdentifier: String
  ) -> (payload: [String: Any], focusWindow: Bool) {
    var userInfo = request.content.userInfo as? [String: Any] ?? [:]
    userInfo.removeValue(forKey: "notificationAction")
    userInfo.removeValue(forKey: "notificationId")
    let incoming = request.content.categoryIdentifier == Self.incomingCategory
    var focusWindow = true
    if incoming {
      // 动作与通知标识来自系统响应，覆盖 payload 中同名字段，避免伪造确认操作。
      let action: String
      switch actionIdentifier {
      case Self.acceptAction: action = "accept"
      case Self.rejectAction: action = "reject"
      case UNNotificationDefaultActionIdentifier: action = "open"
      case UNNotificationDismissActionIdentifier: action = "dismiss"
      default: action = "unknown"
      }
      userInfo["notificationAction"] = action
      userInfo["notificationId"] = request.identifier
      focusWindow = action == "open"
    }
    return (userInfo, focusWindow)
  }
}
