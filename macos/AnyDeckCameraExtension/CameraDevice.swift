import CoreMediaIO
import CoreVideo
import Foundation

/// 单一串行队列持有最新一帧，隔离 CMIO 回调和定时供帧并释放断流图像。
final class AnyDeckCameraDevice: NSObject, CMIOExtensionDeviceSource {
  private(set) var device: CMIOExtensionDevice!
  private(set) var source: AnyDeckCameraStream!
  private(set) var sink: AnyDeckCameraStream!
  let queue = DispatchQueue(label: "com.github.anydeck.camera.frames")
  private let lock = NSLock()
  private var consumers = 0
  private let frames = AnyDeckCameraFrameStore()
  private var timer: DispatchSourceTimer?
  private var placeholder: CVPixelBuffer?
  private var generation = 0
  private var producer: CMIOExtensionClient?
  let format: CMVideoFormatDescription

  init(registerStreams: Bool) throws {
    var description: CMVideoFormatDescription?
    let status = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
      codecType: kCVPixelFormatType_32BGRA,
      width: Int32(AnyDeckCameraContract.width), height: Int32(AnyDeckCameraContract.height),
      extensions: nil, formatDescriptionOut: &description)
    guard status == noErr, let description else { throw NSError(domain: "AnyDeckCamera", code: Int(status)) }
    format = description
    super.init()
    device = CMIOExtensionDevice(localizedName: "AnyDeck Camera",
      deviceID: UUID(uuidString: AnyDeckCameraContract.deviceUID)!,
      legacyDeviceID: AnyDeckCameraContract.deviceUID, source: self)
    source = AnyDeckCameraStream(camera: self, direction: .source)
    sink = AnyDeckCameraStream(camera: self, direction: .sink)
    if registerStreams {
      try device.addStream(source.stream)
      try device.addStream(sink.stream)
    }
  }

  var availableProperties: Set<CMIOExtensionProperty> { [.deviceTransportType, .deviceModel] }
  func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
    let result = CMIOExtensionDeviceProperties(dictionary: [:])
    result.transportType = 0x76697274 // CoreAudio 的 virt transport FourCC
    result.model = "AnyDeck Camera"
    return result
  }
  func setDeviceProperties(_ properties: CMIOExtensionDeviceProperties) throws {}

  var demand: NSString {
    lock.lock(); defer { lock.unlock() }
    return consumers > 0 ? "1" : "0"
  }

  func changeDemand(_ delta: Int) {
    lock.lock()
    consumers = max(0, consumers + delta)
    let active = consumers > 0
    lock.unlock()
    source.stream.notifyPropertiesChanged([
      AnyDeckCameraContract.demandProperty: CMIOExtensionPropertyState(value: active ? "1" as NSString : "0" as NSString)
    ])
    queue.async { [weak self] in
      guard let self else { return }
      if active { self.startTimer() } else {
        self.timer?.cancel(); self.timer = nil
        self.frames.clear()
      }
    }
  }

  func authorize(_ client: CMIOExtensionClient) -> Bool {
    guard client.signingID == AnyDeckCameraContract.hostSigningID else { return false }
    lock.lock(); defer { lock.unlock() }
    guard producer == nil || producer?.clientID == client.clientID else { return false }
    producer = client
    return true
  }

  func startSink() throws {
    lock.lock(); let client = producer; lock.unlock()
    guard let client else { throw NSError(domain: "AnyDeckCamera", code: 1) }
    queue.async { [weak self] in
      guard let self else { return }
      self.generation += 1
      self.frames.clear()
      self.consume(client, generation: self.generation)
    }
  }

  func stopSink() {
    lock.lock(); producer = nil; lock.unlock()
    queue.async { [weak self] in
      self?.generation += 1
      self?.frames.clear()
    }
  }

  func disconnect(_ client: CMIOExtensionClient) {
    lock.lock(); let matches = producer?.clientID == client.clientID; lock.unlock()
    if matches { stopSink() }
  }

  private func consume(_ client: CMIOExtensionClient, generation: Int) {
    guard generation == self.generation else { return }
    sink.stream.consumeSampleBuffer(from: client) { [weak self] sample, sequence, _, hasMore, error in
      guard let self else { return }
      self.queue.async {
        guard generation == self.generation else { return }
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        if self.demand == "1", let sample, let image = CMSampleBufferGetImageBuffer(sample) {
          self.frames.receive(image, at: now)
        }
        self.sink.stream.notifyScheduledOutputChanged(CMIOExtensionScheduledOutput(
          sequenceNumber: sequence, hostTimeInNanoseconds: self.nanoseconds(now)))
        if error != nil { self.frames.clear() }
        // 队列为空时延迟下次请求，避免空轮询占满 CPU；最多只有一个请求在途。
        self.queue.asyncAfter(deadline: .now() + (hasMore ? 0 : 1.0 / 30.0)) { [weak self] in
          self?.consume(client, generation: generation)
        }
      }
    }
  }

  private func startTimer() {
    guard timer == nil else { return }
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now(), repeating: 1.0 / Double(AnyDeckCameraContract.fps))
    timer.setEventHandler { [weak self] in self?.emitFrame() }
    self.timer = timer
    timer.resume()
  }

  private func emitFrame() {
    let now = CMClockGetTime(CMClockGetHostTimeClock())
    guard let image = frames.image(at: now) ?? standbyImage() else { return }
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: AnyDeckCameraContract.fps),
      presentationTimeStamp: now, decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    let status = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
      imageBuffer: image, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample)
    if status == noErr, let sample {
      source.stream.send(sample, discontinuity: [], hostTimeInNanoseconds: nanoseconds(now))
    }
  }

  private func nanoseconds(_ time: CMTime) -> UInt64 {
    UInt64(max(0, CMTimeConvertScale(time, timescale: 1_000_000_000, method: .default).value))
  }

  private func standbyImage() -> CVPixelBuffer? {
    if let placeholder { return placeholder }
    var image: CVPixelBuffer?
    let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
    guard CVPixelBufferCreate(kCFAllocatorDefault, AnyDeckCameraContract.width,
      AnyDeckCameraContract.height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &image) == kCVReturnSuccess,
      let image else { return nil }
    CVPixelBufferLockBaseAddress(image, [])
    if let bytes = CVPixelBufferGetBaseAddress(image) {
      let stride = CVPixelBufferGetBytesPerRow(image)
      for y in 0..<AnyDeckCameraContract.height {
        let row = bytes.advanced(by: y * stride).assumingMemoryBound(to: UInt32.self)
        for x in 0..<AnyDeckCameraContract.width {
          // 固定深灰占位；断流后不向会议继续发送手机的最后画面。
          row[x] = 0xff202020
        }
      }
    }
    CVPixelBufferUnlockBaseAddress(image, [])
    placeholder = image
    return image
  }
}
