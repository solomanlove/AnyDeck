import Cocoa
import UserNotifications

/// 独立验证原生通知动作映射，不创建应用、通知中心或系统授权弹窗。
class MainFlutterWindow: NSWindow {}

@main
struct NotificationInteractionTest {
  static func main() {
    let content = UNMutableNotificationContent()
    content.categoryIdentifier = "harmony_share_incoming"
    content.userInfo = [
      "type": "harmony_share_offer", "offerToken": "live-token",
      "notificationAction": "accept", "notificationId": "forged-id"
    ]
    let request = UNNotificationRequest(identifier: "actual-id", content: content, trigger: nil)
    let cases: [(String, String, Bool)] = [
      ("harmony_share_accept", "accept", false),
      ("harmony_share_reject", "reject", false),
      (UNNotificationDefaultActionIdentifier, "open", true),
      (UNNotificationDismissActionIdentifier, "dismiss", false),
      ("unrecognized", "unknown", false)
    ]
    for (nativeAction, expectedAction, expectedFocus) in cases {
      let result = NotificationBridgeService.notificationInteraction(
        request: request, actionIdentifier: nativeAction
      )
      precondition(result.payload["notificationAction"] as? String == expectedAction)
      precondition(result.payload["notificationId"] as? String == "actual-id")
      precondition(result.payload["offerToken"] as? String == "live-token")
      precondition(result.focusWindow == expectedFocus)
    }
    content.categoryIdentifier = ""
    content.userInfo["deviceId"] = "device-1"
    let ordinary = UNNotificationRequest(identifier: "ordinary-id", content: content, trigger: nil)
    let generic = NotificationBridgeService.notificationInteraction(
      request: ordinary, actionIdentifier: UNNotificationDefaultActionIdentifier
    )
    precondition(generic.payload["notificationAction"] == nil)
    precondition(generic.payload["notificationId"] == nil)
    precondition(generic.payload["deviceId"] as? String == "device-1")
    precondition(generic.focusWindow)
    print("6 notification interaction cases passed")
  }
}
