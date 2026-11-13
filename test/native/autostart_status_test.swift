import Foundation
import ServiceManagement

/// 只运行纯状态映射和设置地址，不查询真实登录项、不注册或写用户目录。
@main
struct AutoStartStatusTest {
  static func main() {
    if #available(macOS 13.0, *) {
      precondition(AutoStartBridgeService.statusName(.enabled) == "enabled")
      precondition(AutoStartBridgeService.statusName(.requiresApproval) == "requiresApproval")
      precondition(AutoStartBridgeService.statusName(.notFound) == "unavailable")
      precondition(AutoStartBridgeService.statusName(.notRegistered) == "disabled")
      precondition(AutoStartBridgeService.statusName(.notRegistered, legacyConfigured: true) == "manual")
      precondition(AutoStartBridgeService.statusName(.requiresApproval, legacyConfigured: true) == "requiresApproval")
      precondition(AutoStartBridgeService.settingsURL?.absoluteString == "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    } else {
      precondition(AutoStartBridgeService.settingsURL?.absoluteString == "x-apple.systempreferences:com.apple.preference.users")
    }
    print("AutoStartStatusTest passed")
  }
}
