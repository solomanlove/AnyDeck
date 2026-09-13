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
    if let env = ProcessInfo.processInfo.environment["ANYDECK_DEVICE_BRIDGE"], !env.isEmpty {
      library = dlopen(env, RTLD_NOW | RTLD_GLOBAL)
    }
    if library == nil, let frameworks = Bundle.main.privateFrameworksPath {
      library = dlopen("\(frameworks)/libanydeck_device_bridge.dylib", RTLD_NOW | RTLD_GLOBAL)
    }
    if library == nil {
      let pwdPath = "\(FileManager.default.currentDirectoryPath)/macos/Libs/libanydeck_device_bridge.dylib"
      library = dlopen(pwdPath, RTLD_NOW | RTLD_GLOBAL)
    }
    if library == nil {
      library = dlopen("@rpath/libanydeck_device_bridge.dylib", RTLD_NOW | RTLD_GLOBAL)
    }
    if let library {
      if let copy = dlsym(library, "anydeck_copy_pixel_buffer"),
         let release = dlsym(library, "anydeck_release") {
        copyPixel = unsafeBitCast(copy, to: CopyPixel.self)
        releaseSession = unsafeBitCast(release, to: Release.self)
        NSLog("[RustTexturePlugin] Successfully loaded libanydeck_device_bridge.dylib symbols")
      } else {
        NSLog("[RustTexturePlugin] Failed to dlsym anydeck_copy_pixel_buffer or anydeck_release")
      }
    } else {
      let err = dlerror().map { String(cString: $0) } ?? "unknown"
      NSLog("[RustTexturePlugin] Failed to dlopen libanydeck_device_bridge.dylib: \(err)")
    }
    NotificationCenter.default.addObserver(self, selector: #selector(windowClosing(_:)),
                                          name: NSWindow.willCloseNotification, object: nil)
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = RustTexturePlugin(registrar: registrar)
    let channel = FlutterMethodChannel(name: "anydeck/rust_texture", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private func extractHandle(_ arguments: [String: Any]?) -> UInt64? {
    if let num = arguments?["handle"] as? NSNumber {
      return num.uint64Value
    }
    if let u = arguments?["handle"] as? UInt64 {
      return u
    }
    if let i = arguments?["handle"] as? Int64 {
      return UInt64(bitPattern: i)
    }
    if let i = arguments?["handle"] as? Int {
      return UInt64(i)
    }
    return nil
  }

  private func extractTextureId(_ arguments: [String: Any]?) -> Int64? {
    if let num = arguments?["textureId"] as? NSNumber {
      return num.int64Value
    }
    if let i = arguments?["textureId"] as? Int64 {
      return i
    }
    if let i = arguments?["textureId"] as? Int {
      return Int64(i)
    }
    return nil
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let handle = extractHandle(arguments)
    let textureId = extractTextureId(arguments)

    if call.method == "track" {
      guard let handle else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing or invalid handle", details: nil))
        return
      }
      guard releaseSession != nil else {
        result(FlutterError(code: "RUST_LIBRARY_MISSING", message: "Rust device bridge is unavailable", details: nil))
        return
      }
      tracked.insert(handle)
      result(nil)
    } else if call.method == "untrack" {
      if let handle { tracked.remove(handle) }
      result(nil)
    } else if call.method == "register" {
      guard let handle else {
        NSLog("[RustTexturePlugin] register called with missing/invalid handle: \(String(describing: arguments))")
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing or invalid handle", details: nil))
        return
      }
      guard let copyPixel else {
        NSLog("[RustTexturePlugin] register called but copyPixel is nil")
        result(FlutterError(code: "RUST_LIBRARY_MISSING", message: "Rust device bridge is unavailable", details: nil))
        return
      }
      let texture = RustPixelTexture(handle: handle, copy: copyPixel)
      let id = registry.register(texture)
      textures[id] = texture
      NSLog("[RustTexturePlugin] Registered texture id=\(id) for handle=\(handle)")
      // 注册后立即触发一帧通知，加速首帧渲染呈现
      registry.textureFrameAvailable(id)
      if timer == nil {
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
          guard let self else { return }
          for id in self.textures.keys { self.registry.textureFrameAvailable(id) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
      }
      result(id)
    } else if call.method == "unregister" {
      if let id = textureId {
        if textures.removeValue(forKey: id) != nil { registry.unregisterTexture(id) }
      }
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
  private var hasCopiedFirstFrame = false
  init(handle: UInt64, copy: @escaping @convention(c) (UInt64) -> UnsafeMutableRawPointer?) {
    self.handle = handle
    self.copy = copy
  }
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    guard let buffer = copy(handle) else { return nil }
    if !hasCopiedFirstFrame {
      hasCopiedFirstFrame = true
      NSLog("[RustTexturePlugin] First pixel buffer copied successfully for handle=\(handle) buffer=\(buffer)")
    }
    return Unmanaged<CVPixelBuffer>.fromOpaque(buffer)
  }
}
