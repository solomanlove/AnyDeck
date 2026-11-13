import Foundation

/// 验证激活标识与状态优先级，不创建请求、访问 CMIO 或触发系统授权。
@main
struct VirtualCameraActivationTests {
  static func main() {
    let defaultID = "com.github.anydeck.camera-extension"
    precondition(AnyDeckCameraContract.resolveExtensionID(infoDictionary: nil) == defaultID,
      "命令行测试没有宿主 Info.plist 时保留默认扩展 ID")
    precondition(AnyDeckCameraContract.resolveExtensionID(infoDictionary: [:]) == defaultID)
    precondition(AnyDeckCameraContract.resolveExtensionID(infoDictionary:
      ["AnyDeckCameraExtensionBundleIdentifier": ""]) == defaultID)
    let overrideID = "com.github.anydeck.camera-extension.testing"
    precondition(AnyDeckCameraContract.resolveExtensionID(infoDictionary:
      ["AnyDeckCameraExtensionBundleIdentifier": overrideID]) == overrideID,
      "覆盖值必须用于激活请求，不能继续使用默认 ID")
    let expectedID = CommandLine.arguments.dropFirst().first ?? defaultID
    precondition(AnyDeckCameraContract.extensionID == expectedID,
      "激活契约必须读取当前宿主 Bundle 的扩展 ID")
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
