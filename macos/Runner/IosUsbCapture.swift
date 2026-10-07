import AVFoundation
import CoreMediaIO
import CoreVideo

/// iPhone USB 屏幕采集：AVFoundation 交付 CVPixelBuffer，只保留最新帧。
/// 通过物理 USB 身份和唯一 iOS 屏幕候选关联，不按名称选择摄像头。
final class IosUsbCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  private let queue = DispatchQueue(label: "anydeck.ios.usb.capture")
  private let frames = DispatchQueue(label: "anydeck.ios.usb.frames")
  private let lock = NSLock()
  private var session: AVCaptureSession?
  private var pixel: CVPixelBuffer?
  private var count = 0
  private var lastFrame: TimeInterval = 0
  private var startedAt = Date().timeIntervalSince1970
  private var failure: String?
  private var stage = "created"
  private var discovered: [[String: Any]] = []
  private var usbSerials: [String] = []
  private var closed = false
  private var notificationPending = false
  private var observers: [NSObjectProtocol] = []
  var onFrame: (() -> Void)?

  static func enableDevices() throws {
    var address = CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    var enabled: UInt32 = 1
    let status = CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject),
      &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &enabled)
    if status != noErr { throw NSError(domain: "IosUsbCapture", code: Int(status)) }
  }

  static func devices() -> [AVCaptureDevice] {
    // 旧 iPhone 暴露为 muxed 设备；保留兼容枚举，不能只查普通摄像头类型。
    var seen = Set<String>()
    return (AVCaptureDevice.devices(for: .muxed) + AVCaptureDevice.devices(for: .video))
      .filter { seen.insert($0.uniqueID).inserted }
  }

  /// 延迟枚举允许 iOSScreenCaptureAssistant 完成设备发现；启动工作不阻塞主线程。
  func start(udid: String, completion: @escaping (Error?) -> Void) {
    queue.async { [self] in
      do {
        setStage("enablingDevices")
        try Self.enableDevices()
        setStage("discovering")
        var device: AVCaptureDevice?
        let deadline = Date().addingTimeInterval(8)
        repeat {
          if isClosed { return }
          let available = Self.devices()
          let identities = available.map(Self.describe)
          let physical = IosUsbDeviceSelection.connectedSerials()
          lock.lock(); discovered = identities; usbSerials = physical; lock.unlock()
          let id = try IosUsbDeviceSelection.selectID(udid: udid, usbSerials: physical, devices: identities)
          device = available.first { $0.uniqueID == id }
          if device == nil { Thread.sleep(forTimeInterval: 0.2) }
        } while device == nil && Date() < deadline
        guard let device else {
          throw NSError(domain: "IosUsbCapture", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "iosUsbDeviceMissing"])
        }
        let capture = AVCaptureSession()
        setStage("creatingInput")
        capture.beginConfiguration()
        let input = try AVCaptureDeviceInput(device: device)
        guard capture.canAddInput(input) else {
          throw NSError(domain: "IosUsbCapture", code: 2)
        }
        capture.addInput(input)
        setStage("configuringOutput")
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
          kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
          kCVPixelBufferIOSurfacePropertiesKey as String: [:],
          kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        output.setSampleBufferDelegate(self, queue: frames)
        guard capture.canAddOutput(output) else {
          throw NSError(domain: "IosUsbCapture", code: 3)
        }
        capture.addOutput(output)
        capture.commitConfiguration()
        session = capture
        observers.append(NotificationCenter.default.addObserver(
          forName: AVCaptureSession.runtimeErrorNotification, object: capture, queue: nil) { [weak self] note in
            self?.setFailure((note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
              ?? "iosUsbCaptureStopped")
          })
        observers.append(NotificationCenter.default.addObserver(
          forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil) { [weak self] _ in
            self?.setFailure("iosUsbDeviceMissing")
          })
        lock.lock(); startedAt = Date().timeIntervalSince1970; lock.unlock()
        setStage("startingSession")
        capture.startRunning()
        lock.lock(); if count == 0 { stage = "waitingFirstFrame" }; lock.unlock()
        DispatchQueue.main.async { completion(nil) }
      } catch {
        setFailure(error.localizedDescription)
        DispatchQueue.main.async { completion(error) }
      }
    }
  }

  private var isClosed: Bool {
    lock.lock(); defer { lock.unlock() }
    return closed
  }

  private func setFailure(_ message: String) {
    lock.lock(); failure = message; lock.unlock()
  }

  private func setStage(_ value: String) {
    lock.lock(); stage = value; lock.unlock()
  }

  /// 只记录设备身份和能力，不采集或保存屏幕内容。
  static func describe(_ device: AVCaptureDevice) -> [String: Any] {
    ["id": device.uniqueID, "name": device.localizedName,
     "model": device.modelID, "manufacturer": device.manufacturer,
     "transport": device.transportType, "type": device.deviceType.rawValue,
     "video": device.hasMediaType(.video), "muxed": device.hasMediaType(.muxed),
     "connected": device.isConnected, "suspended": device.isSuspended]
  }

  func diagnostics() -> [String: Any] {
    var value = status()
    lock.lock(); value["devices"] = discovered; value["usbSerials"] = usbSerials; lock.unlock()
    value["cameraAuthorization"] = AVCaptureDevice.authorizationStatus(for: .video).rawValue
    return value
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                     from connection: AVCaptureConnection) {
    guard let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    lock.lock()
    if closed { lock.unlock(); return }
    pixel = image
    stage = "streaming"
    count += 1
    lastFrame = Date().timeIntervalSince1970
    let notify = !notificationPending
    notificationPending = true
    lock.unlock()
    // 主线程繁忙时合并通知，只保留最新帧，不能让通知队列随视频时长增长。
    if notify {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.lock.lock()
        self.notificationPending = false
        let active = !self.closed
        self.lock.unlock()
        if active { self.onFrame?() }
      }
    }
  }

  func copyPixel() -> Unmanaged<CVPixelBuffer>? {
    lock.lock(); defer { lock.unlock() }
    return pixel.map { Unmanaged.passRetained($0) }
  }

  /// 供低频状态轮询与 CLI PoC 使用；不复制图像数据。
  func status() -> [String: Any] {
    lock.lock(); defer { lock.unlock() }
    let now = Date().timeIntervalSince1970
    return ["width": pixel.map { CVPixelBufferGetWidth($0) } ?? 0,
            "height": pixel.map { CVPixelBufferGetHeight($0) } ?? 0,
            "frames": count, "fps": Double(count) / max(0.001, now - startedAt),
            "stage": stage,
            "frameAgeMs": lastFrame == 0 ? -1 : (now - lastFrame) * 1000,
            "error": failure ?? "", "closed": closed]
  }

  func stop() {
    lock.lock(); closed = true; pixel = nil; lock.unlock()
    queue.async { [self] in
      session?.stopRunning()
      session = nil
      observers.forEach { NotificationCenter.default.removeObserver($0) }
      observers.removeAll()
    }
  }
}
