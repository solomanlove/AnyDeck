import Cocoa
import FlutterMacOS
import CoreVideo

/// 平台必需的 Texture 适配：只注册/通知 Flutter，像素及设备逻辑归 Rust 所有。
final class RustTexturePlugin: NSObject, FlutterPlugin {
  private typealias CopyPixel = @convention(c) (UInt64) -> UnsafeMutableRawPointer?
  private typealias Release = @convention(c) (UInt64) -> Void
  private let registry: FlutterTextureRegistry
  private let registrar: FlutterPluginRegistrar
  private var tracked = Set<UInt64>()
  private var textures: [Int64: RustPixelTexture] = [:]
  private var timer: Timer?
  private var copyPixel: CopyPixel?
  private var releaseSession: Release?
  private var library: UnsafeMutableRawPointer?

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    registry = registrar.textures
    super.init()
    if let frameworks = Bundle.main.privateFrameworksPath {
      library = dlopen("\(frameworks)/libanydeck_device_bridge.dylib", RTLD_NOW | RTLD_LOCAL)
      if let library,
         let copy = dlsym(library, "anydeck_copy_pixel_buffer"),
         let release = dlsym(library, "anydeck_release") {
        copyPixel = unsafeBitCast(copy, to: CopyPixel.self)
        releaseSession = unsafeBitCast(release, to: Release.self)
      }
    }
    NotificationCenter.default.addObserver(self, selector: #selector(windowClosing(_:)),
                                          name: NSWindow.willCloseNotification, object: nil)
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = RustTexturePlugin(registrar: registrar)
    let channel = FlutterMethodChannel(name: "anydeck/rust_texture", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    if call.method == "track", let handle = arguments?["handle"] as? UInt64 {
      guard releaseSession != nil else {
        result(FlutterError(code: "RUST_LIBRARY_MISSING", message: "Rust device bridge is unavailable", details: nil))
        return
      }
      tracked.insert(handle)
      result(nil)
    } else if call.method == "untrack", let handle = arguments?["handle"] as? UInt64 {
      tracked.remove(handle)
      result(nil)
    } else if call.method == "register", let handle = arguments?["handle"] as? UInt64 {
      guard let copyPixel else {
        result(FlutterError(code: "RUST_LIBRARY_MISSING", message: "Rust device bridge is unavailable", details: nil))
        return
      }
      let texture = RustPixelTexture(handle: handle, copy: copyPixel)
      let id = registry.register(texture)
      textures[id] = texture
      if timer == nil {
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
          guard let self else { return }
          for id in self.textures.keys { self.registry.textureFrameAvailable(id) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
      }
      result(id)
    } else if call.method == "unregister", let id = arguments?["textureId"] as? Int64 {
      if textures.removeValue(forKey: id) != nil { registry.unregisterTexture(id) }
      if textures.isEmpty { timer?.invalidate(); timer = nil }
      result(nil)
    } else {
      result(FlutterMethodNotImplemented)
    }
  }

  @objc private func windowClosing(_ notification: Notification) {
    if let window = registrar.view?.window, notification.object as? NSWindow === window { cleanup() }
  }

  private func cleanup() {
    timer?.invalidate()
    timer = nil
    for id in textures.keys { registry.unregisterTexture(id) }
    for handle in tracked { releaseSession?(handle) }
    tracked.removeAll()
    textures.removeAll()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    cleanup()
    // Rust 的清理线程可能仍在执行，进程退出前不卸载 dylib。
  }
}

/// Rust 返回 retain 后的 CVPixelBuffer，由 Flutter 消费后释放，零拷贝显示。
private final class RustPixelTexture: NSObject, FlutterTexture {
  let handle: UInt64
  private let copy: @convention(c) (UInt64) -> UnsafeMutableRawPointer?
  init(handle: UInt64, copy: @escaping @convention(c) (UInt64) -> UnsafeMutableRawPointer?) {
    self.handle = handle
    self.copy = copy
  }
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    guard let buffer = copy(handle) else { return nil }
    return Unmanaged<CVPixelBuffer>.fromOpaque(buffer)
  }
}
