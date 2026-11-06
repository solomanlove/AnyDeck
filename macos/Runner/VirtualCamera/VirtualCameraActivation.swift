import Foundation
import SystemExtensions
import Security

/// 激活状态与系统异步批准保持一致；应用安装路径、签名失败均保留明确错误状态。
final class VirtualCameraActivation: NSObject, OSSystemExtensionRequestDelegate {
  private(set) var state = "notInstalled"
  private(set) var error: String?
  private var pending = false
  func request(activate: Bool) {
    guard !pending else { return }
    guard Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications" else {
      state = "error"; error = "virtualCameraApplicationsRequired"; return
    }
    guard Self.hasInstallEntitlement() else {
      state = "error"; error = "virtualCameraSigningRequired"; return
    }
    pending = true; error = nil
    let request = activate
      ? OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: AnyDeckCameraContract.extensionID, queue: .main)
      : OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: AnyDeckCameraContract.extensionID, queue: .main)
    request.delegate = self
    OSSystemExtensionManager.shared.submitRequest(request)
  }
  private static func hasInstallEntitlement() -> Bool {
    var running: SecCode?
    var code: SecStaticCode?
    var info: CFDictionary?
    guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
          SecCodeCopyStaticCode(running, [], &code) == errSecSuccess, let code,
          SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let details = info as? [String: Any],
          let entitlements = details[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else { return false }
    return entitlements["com.apple.developer.system-extension.install"] as? Bool == true
  }
  func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) { state = "needsApproval" }
  func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
    pending = false
    state = result == .willCompleteAfterReboot ? "needsReboot" : "notInstalled"
    // finished 只证明请求完成；ready 由实际 CMIO 设备发现确认。
  }
  func request(_ request: OSSystemExtensionRequest, didFailWithError failure: Error) {
    pending = false; state = "error"; error = "virtualCameraActivationFailed"
    NSLog("[AnyDeckCamera] activation failed: %@", failure.localizedDescription)
  }
  func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
               withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }
}
