import Cocoa
import AVFoundation
import FlutterMacOS

/// 每个 Flutter Engine 独立持有 Texture，关闭所属窗口立即停止采集。
final class IosUsbCapturePlugin: NSObject, FlutterPlugin {
  private let registrar: FlutterPluginRegistrar
  private var captures: [String: IosUsbCapture] = [:]
  private var textures: [String: Int64] = [:]
  private var pending: [String: FlutterResult] = [:]
  private var closing = false

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
    NotificationCenter.default.addObserver(self, selector: #selector(windowClosing(_:)),
      name: NSWindow.willCloseNotification, object: nil)
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = IosUsbCapturePlugin(registrar: registrar)
    let channel = FlutterMethodChannel(name: "anydeck/ios_usb_capture", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(plugin, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let udid = args["udid"] as? String,
          !udid.isEmpty else {
      result(FlutterError(code: "iosInvalidDevice", message: nil, details: nil)); return
    }
    switch call.method {
    case "start":
      guard !closing else { result(FlutterError(code: "iosUsbCaptureStopped", message: nil, details: nil)); return }
      if let id = textures[udid], pending[udid] == nil {
        result(id); return
      }
      guard captures[udid] == nil else {
        result(FlutterError(code: "iosUsbStarting", message: nil, details: nil)); return
      }
      let capture = IosUsbCapture()
      captures[udid] = capture
      pending[udid] = result
      let begin = { [weak self, weak capture] in
        guard let self, let capture, self.captures[udid] === capture else { return }
        self.begin(udid, capture: capture)
      }
      if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
          DispatchQueue.main.async {
            guard let self, self.captures[udid] === capture else { return }
            if granted { begin() } else { self.stop(udid, code: "iosUsbPermissionDenied") }
          }
        }
      } else if AVCaptureDevice.authorizationStatus(for: .video) == .denied ||
                  AVCaptureDevice.authorizationStatus(for: .video) == .restricted {
        stop(udid, code: "iosUsbPermissionDenied")
      } else { begin() }
    case "status": result(captures[udid]?.status())
    case "stop": stop(udid); result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func begin(_ udid: String, capture: IosUsbCapture) {
    let id = registrar.textures.register(IosUsbPixelTexture(capture))
    guard id != 0 else { stop(udid, code: "iosUsbTextureFailed"); return }
    textures[udid] = id
    capture.onFrame = { [weak self, weak capture] in
      guard let self, let capture, self.captures[udid] === capture else { return }
      self.registrar.textures.textureFrameAvailable(id)
      // 只有真实首帧到达后，Dart 才能将会话显示为已启动。
      self.pending.removeValue(forKey: udid)?(id)
    }
    capture.start(udid: udid) { [weak self, weak capture] error in
      guard let self, let capture, self.captures[udid] === capture else { return }
      if let error { self.stop(udid, code: error.localizedDescription) }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self, weak capture] in
      guard let self, let capture, self.captures[udid] === capture, self.pending[udid] != nil else { return }
      self.stop(udid, code: "iosUsbFirstFrameTimeout")
    }
  }

  private func stop(_ udid: String, code: String = "iosUsbCaptureStopped") {
    let details = captures[udid]?.diagnostics()
    captures.removeValue(forKey: udid)?.stop()
    if let id = textures.removeValue(forKey: udid) { registrar.textures.unregisterTexture(id) }
    pending.removeValue(forKey: udid)?(FlutterError(code: code, message: nil, details: details))
  }

  @objc private func windowClosing(_ note: Notification) {
    guard note.object as? NSWindow === registrar.view?.window else { return }
    closing = true
    Array(captures.keys).forEach { stop($0) }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    captures.values.forEach { $0.stop() }
  }
}

/// Texture 只交付 retain 后的最新 CVPixelBuffer，交由 Flutter 释放。
private final class IosUsbPixelTexture: NSObject, FlutterTexture {
  let capture: IosUsbCapture
  init(_ capture: IosUsbCapture) { self.capture = capture }
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? { capture.copyPixel() }
}
