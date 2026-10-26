import Cocoa
import FlutterMacOS
import CoreVideo
import AVFoundation

/// 平台必需的 Texture 适配：只注册/通知 Flutter，像素及设备逻辑归 Rust 所有。
final class RustTexturePlugin: NSObject, FlutterPlugin {
  private typealias CopyPixel = @convention(c) (UInt64) -> UnsafeMutableRawPointer?
  private typealias Release = @convention(c) (UInt64) -> Void
  private let registry: FlutterTextureRegistry
  private let registrar: FlutterPluginRegistrar
  private var tracked = Set<UInt64>()
  private var textures: [Int64: RustPixelTexture] = [:]
  private var recorders: [UInt64: AirplayTextureRecorder] = [:]
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
      if let handle {
        tracked.remove(handle)
        recorders.removeValue(forKey: handle)?.stop { _, _ in }
      }
      result(nil)
    } else if call.method == "startRecording" {
      guard let handle, let path = arguments?["path"] as? String, !path.isEmpty,
            textures.values.contains(where: { $0.handle == handle }), recorders[handle] == nil else {
        result(FlutterError(code: "airplayRecordingUnavailable", message: nil, details: nil))
        return
      }
      do {
        let recorder = try AirplayTextureRecorder(path: path)
        recorders[handle] = recorder
        result(nil)
      } catch {
        result(FlutterError(code: "airplayRecordingFailed", message: error.localizedDescription, details: nil))
      }
    } else if call.method == "stopRecording" {
      guard let handle, let recorder = recorders.removeValue(forKey: handle) else {
        result(FlutterError(code: "airplayRecordingUnavailable", message: nil, details: nil))
        return
      }
      recorder.stop { path, error in
        if let error {
          result(FlutterError(code: "airplayRecordingFailed", message: error.localizedDescription, details: nil))
        } else { result(path) }
      }
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
          for (id, texture) in self.textures {
            self.registry.textureFrameAvailable(id)
            self.recorders[texture.handle]?.append(texture: texture)
          }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
      }
      result(id)
    } else if call.method == "unregister" {
      if let id = textureId {
        if let texture = textures.removeValue(forKey: id) {
          registry.unregisterTexture(id)
          if !textures.values.contains(where: { $0.handle == texture.handle }) {
            recorders.removeValue(forKey: texture.handle)?.stop { _, _ in }
          }
        }
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
    for recorder in recorders.values { recorder.stop { _, _ in } }
    recorders.removeAll()
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

/// 直接录制 Rust Texture 的 CVPixelBuffer，避免将 AirPlay 视频帧送入 Dart。
private final class AirplayTextureRecorder {
  private let url: URL
  private var writer: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var startedAt: TimeInterval?
  private var lastFrame: TimeInterval = 0
  private var failure: Error?
  private var stopped = false

  init(path: String) throws {
    url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: path) {
      throw NSError(domain: "AirplayTextureRecorder", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "airplayRecordingFileExists"])
    }
  }

  func append(texture: RustPixelTexture) {
    guard !stopped, failure == nil else { return }
    let now = ProcessInfo.processInfo.systemUptime
    if now - lastFrame < 1.0 / 30.0 { return }
    lastFrame = now
    guard let retained = texture.copyPixelBuffer() else { return }
    let pixel = retained.takeRetainedValue()
    do {
      if writer == nil { try configure(pixel: pixel, startedAt: now) }
      guard let writer, let input, let adaptor else { return }
      if writer.status == .failed {
        failure = writer.error
        return
      }
      guard input.isReadyForMoreMediaData else { return }
      let time = CMTime(seconds: now - (startedAt ?? now), preferredTimescale: 600)
      if !adaptor.append(pixel, withPresentationTime: time) {
        failure = writer.error ?? NSError(domain: "AirplayTextureRecorder", code: 2)
      }
    } catch { failure = error }
  }

  private func configure(pixel: CVPixelBuffer, startedAt: TimeInterval) throws {
    let width = CVPixelBufferGetWidth(pixel)
    let height = CVPixelBufferGetHeight(pixel)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: min(width * height * 4, 20_000_000)],
    ])
    input.expectsMediaDataInRealTime = true
    guard writer.canAdd(input) else {
      throw NSError(domain: "AirplayTextureRecorder", code: 3)
    }
    writer.add(input)
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ])
    guard writer.startWriting() else {
      throw writer.error ?? NSError(domain: "AirplayTextureRecorder", code: 4)
    }
    writer.startSession(atSourceTime: .zero)
    self.writer = writer
    self.input = input
    self.adaptor = adaptor
    self.startedAt = startedAt
  }

  func stop(completion: @escaping (String?, Error?) -> Void) {
    guard !stopped else { completion(nil, failure); return }
    stopped = true
    guard let writer, let input else {
      try? FileManager.default.removeItem(at: url)
      completion(nil, failure ?? NSError(domain: "AirplayTextureRecorder", code: 5,
        userInfo: [NSLocalizedDescriptionKey: "airplayRecordingNoFrames"]))
      return
    }
    guard writer.status == .writing else {
      try? FileManager.default.removeItem(at: url)
      completion(nil, failure ?? writer.error)
      return
    }
    input.markAsFinished()
    writer.finishWriting { [self] in
      DispatchQueue.main.async { [self] in
        let error = self.failure ?? writer.error
        if writer.status != .completed || error != nil {
          try? FileManager.default.removeItem(at: self.url)
          completion(nil, error ?? NSError(domain: "AirplayTextureRecorder", code: 6))
        } else {
          completion(self.url.path, nil)
        }
      }
    }
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
