import Foundation

/// 仅验证激活状态优先级，不创建请求、访问 CMIO 或触发系统授权。
@main
struct VirtualCameraActivationTests {
  static func main() {
    for installed in [false, true] {
      precondition(VirtualCameraActivation.resolvedState("needsApproval", installed: installed) == "needsApproval",
        "升级前的设备可见不能证明新扩展已批准")
      precondition(VirtualCameraActivation.resolvedState("needsReboot", installed: installed) == "needsReboot",
        "旧设备可见不能跳过新扩展要求的重启")
    }
    precondition(VirtualCameraActivation.resolvedState("notInstalled", installed: true) == "ready")
    precondition(VirtualCameraActivation.resolvedState("notInstalled", installed: false) == "notInstalled")
    precondition(VirtualCameraActivation.resolvedState("error", installed: false) == "error")
    print("Virtual camera activation priority: passed")
  }
}
