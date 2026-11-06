import CoreMedia
import CoreVideo
import Foundation

/// 使用内存像素与假下游验证会议生命周期，不访问 ADB、传感器或系统摄像头。
@main
struct VirtualCameraHostTests {
  final class Session: VirtualCameraSession {
    var status: UInt8 = 0
    var frames: UInt64 = 0
    var image: CVPixelBuffer?
    var stops = 0
    var releases = 0
    func copyFrame() -> CVPixelBuffer? { image }
    func stop() { stops += 1 }
    func release() { releases += 1 }
  }
  final class Output: VirtualCameraOutput {
    var available = true
    var clients = 0
    var accepts = true
    var opens = 0
    var writes = 0
    var closes = 0
    func discover() -> Bool { available }
    func demand() -> Int { clients }
    func open() throws { opens += 1 }
    func write(_ sample: CMSampleBuffer) throws -> Bool {
      writes += 1
      return accepts
    }
    func close() { closes += 1 }
  }

  static let back = VirtualCameraCoordinator.Configuration(adb: "/test/adb", device: "phone", jar: "/test/server.jar", front: false)
  static let front = VirtualCameraCoordinator.Configuration(adb: "/test/adb", device: "phone", jar: "/test/server.jar", front: true)

  static func pixel(_ width: Int = 1280, _ height: Int = 720) -> CVPixelBuffer {
    var image: CVPixelBuffer?
    let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary
    precondition(CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &image) == 0)
    let result = image!
    CVPixelBufferLockBaseAddress(result, [])
    let bytes = CVPixelBufferGetBaseAddress(result)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(result)
    for y in 0..<height {
      for x in 0..<width {
        let offset = y * stride + x * 4
        bytes[offset] = 0; bytes[offset + 1] = 0; bytes[offset + 2] = 255; bytes[offset + 3] = 255
      }
    }
    CVPixelBufferUnlockBaseAddress(result, [])
    return result
  }

  static func demandLifecycle() {
    let output = Output(), source = Session()
    var starts = 0
    let coordinator = VirtualCameraCoordinator(output: output, automaticTimer: false) { _ in starts += 1; return source }
    defer { coordinator.shutdown() }
    let now = ProcessInfo.processInfo.systemUptime
    coordinator.configure(back, enabled: true)
    coordinator.tick(now: now)
    precondition(starts == 0, "启用待机不得打开手机镜头")
    output.clients = 2
    coordinator.tick(now: now + 0.6)
    precondition(starts == 1)
    source.status = 1; source.frames = 1; source.image = pixel()
    coordinator.tick(now: now + 0.7)
    precondition(coordinator.snapshot()["streaming"] as? Bool == true)
    coordinator.tick(now: now + 0.8)
    precondition(output.writes == 1, "同一解码帧不得重复排队")
    output.clients = 1
    coordinator.tick(now: now + 1.2)
    precondition(source.stops == 0, "仍有视频客户端时不能停镜头")
    output.clients = 0
    coordinator.tick(now: now + 1.8)
    coordinator.tick(now: now + 2.8)
    precondition(source.stops == 0, "短时需求抖动应有宽限期")
    coordinator.tick(now: now + 3.9)
    precondition(source.stops == 1)
    precondition(coordinator.snapshot()["streaming"] as? Bool == false)
    source.status = 2
    coordinator.tick(now: now + 4)
    precondition(source.releases == 1)
  }

  static func cancelAndSwitch() {
    let output = Output(), first = Session(), second = Session()
    output.clients = 1
    var choices: [Bool] = []
    let coordinator = VirtualCameraCoordinator(output: output, automaticTimer: false) { choice in
      choices.append(choice.front)
      return choices.count == 1 ? first : second
    }
    defer { coordinator.shutdown() }
    let now = ProcessInfo.processInfo.systemUptime
    coordinator.configure(back, enabled: true)
    coordinator.tick(now: now)
    coordinator.configure(front, enabled: true)
    coordinator.tick(now: now + 0.1)
    precondition(first.stops == 1 && choices == [false], "切镜头必须等待旧 worker 清理完成")
    first.frames = 10; first.image = pixel()
    coordinator.tick(now: now + 0.2)
    precondition(output.writes == 0, "已经取消会话的迟到帧不得进入会议")
    first.status = 2
    coordinator.tick(now: now + 0.3)
    precondition(first.releases == 1 && choices == [false, true])
    coordinator.configure(nil, enabled: false)
    second.frames = 1; second.image = pixel()
    coordinator.tick(now: now + 0.4)
    precondition(second.stops == 1 && output.writes == 0)
    second.status = 2
    coordinator.tick(now: now + 0.5)
    precondition(second.releases == 1)
    precondition(coordinator.snapshot()["enabled"] as? Bool == false)
  }

  static func boundedRetry() {
    let output = Output(); output.clients = 1
    var attempts = 0
    let coordinator = VirtualCameraCoordinator(output: output, automaticTimer: false) { _ in
      attempts += 1
      throw VirtualCameraFailure("cameraStartFailed")
    }
    defer { coordinator.shutdown() }
    let now = ProcessInfo.processInfo.systemUptime
    coordinator.configure(back, enabled: true)
    coordinator.tick(now: now)
    coordinator.tick(now: now + 1)
    precondition(attempts == 1)
    coordinator.tick(now: now + 3.1)
    coordinator.tick(now: now + 6.2)
    coordinator.tick(now: now + 100)
    precondition(attempts == 3, "启动失败必须停止无限重试")
    precondition(coordinator.snapshot()["error"] as? String == "cameraStartFailed")
  }

  static func firstFrameAndFreeze() {
    let output = Output(), source = Session(); output.clients = 1
    let coordinator = VirtualCameraCoordinator(output: output, automaticTimer: false) { _ in source }
    defer { coordinator.shutdown() }
    let now = ProcessInfo.processInfo.systemUptime
    coordinator.configure(back, enabled: true)
    coordinator.tick(now: now)
    coordinator.tick(now: now + 76)
    precondition(source.stops == 1, "首帧未到必须超时回收")
    precondition(coordinator.snapshot()["streaming"] as? Bool == false)

    let otherOutput = Output(), live = Session(); otherOutput.clients = 1
    let other = VirtualCameraCoordinator(output: otherOutput, automaticTimer: false) { _ in live }
    defer { other.shutdown() }
    other.configure(back, enabled: true)
    other.tick(now: now)
    live.frames = 1; live.image = pixel()
    other.tick(now: now + 0.1)
    other.tick(now: now + 3.2)
    precondition(live.stops == 1, "实时画面冻结不能一直报告正在推流")
  }

  static func backpressureAndDisconnect() {
    let output = Output(), source = Session(); output.clients = 1; output.accepts = false
    let coordinator = VirtualCameraCoordinator(output: output, automaticTimer: false) { _ in source }
    defer { coordinator.shutdown() }
    let now = ProcessInfo.processInfo.systemUptime
    coordinator.configure(back, enabled: true); coordinator.tick(now: now)
    source.frames = 1; source.image = pixel()
    coordinator.tick(now: now + 0.1)
    precondition(coordinator.snapshot()["streaming"] as? Bool == false, "满队列丢弃不能记成已交付")
    output.accepts = true; source.frames = 2
    coordinator.tick(now: now + 0.2)
    precondition(coordinator.snapshot()["frames"] as? UInt64 == 1)
    source.status = 3
    coordinator.tick(now: now + 0.3)
    precondition(source.stops == 1)
    precondition(coordinator.snapshot()["error"] as? String == "cameraDisconnected")
  }

  static func missingPixelsCannotRefreshHeartbeat() {
    let output = Output(), source = Session(); output.clients = 1
    let coordinator = VirtualCameraCoordinator(output: output, automaticTimer: false) { _ in source }
    defer { coordinator.shutdown() }
    let now = ProcessInfo.processInfo.systemUptime
    coordinator.configure(back, enabled: true); coordinator.tick(now: now)
    for step in 1...4 {
      source.frames = UInt64(step)
      coordinator.tick(now: now + Double(step))
    }
    precondition(source.stops == 1, "仅帧计数增加而没有像素时不能维持假活跃状态")
    precondition(output.writes == 0)
    precondition(coordinator.snapshot()["error"] as? String == "virtualCameraFrameFailed")
  }

  static func formatter() throws {
    let formatter = try VirtualCameraFrameFormatter()
    let time = CMTime(value: 123456789, timescale: 1_000_000_000)
    let original = pixel()
    let direct = try formatter.sample(original, time: time)
    precondition(CMSampleBufferGetImageBuffer(direct) === original, "匹配格式无需再次分配像素")
    precondition(CMSampleBufferGetPresentationTimeStamp(direct) == time)
    precondition(CMSampleBufferGetDuration(direct) == CMTime(value: 1, timescale: 30))
    precondition(!CMSampleBufferGetDecodeTimeStamp(direct).isValid)
    let scaled = try formatter.sample(pixel(640, 480), time: time + CMTime(value: 1, timescale: 30))
    let image = CMSampleBufferGetImageBuffer(scaled)!
    let format = CMSampleBufferGetFormatDescription(scaled)!
    precondition(CMVideoFormatDescriptionGetDimensions(format).width == 1280)
    precondition(CMVideoFormatDescriptionGetDimensions(format).height == 720)
    precondition(CVPixelBufferGetPixelFormatType(image) == kCVPixelFormatType_32BGRA)
    precondition(CVPixelBufferGetIOSurface(image) != nil)
    CVPixelBufferLockBaseAddress(image, .readOnly)
    let bytes = CVPixelBufferGetBaseAddress(image)!.assumingMemoryBound(to: UInt8.self)
    let row = CVPixelBufferGetBytesPerRow(image) * 360
    precondition(bytes[row + 10 * 4 + 2] < 5, "4:3 输入左右留黑，避免拉伸")
    precondition(bytes[row + 640 * 4 + 2] > 245, "画面中心须保留真实颜色")
    CVPixelBufferUnlockBaseAddress(image, .readOnly)
  }

  static func boundedPixelPool() throws {
    let formatter = try VirtualCameraFrameFormatter(), input = pixel(640, 480)
    var held: [CMSampleBuffer] = []
    for i in 0..<6 { held.append(try formatter.sample(input, time: CMTime(value: Int64(i), timescale: 30))) }
    try withExtendedLifetime(held) {
      do {
        _ = try formatter.sample(input, time: CMTime(value: 6, timescale: 30))
        preconditionFailure("下游不释放帧时，像素池不能无限增长")
      } catch let error as VirtualCameraFailure { precondition(error.key == "virtualCameraFrameFailed") }
    }
    held.removeAll()
    _ = try formatter.sample(input, time: CMTime(value: 7, timescale: 30))
  }

  static func main() throws {
    demandLifecycle()
    cancelAndSwitch()
    boundedRetry()
    firstFrameAndFreeze()
    backpressureAndDisconnect()
    missingPixelsCannotRefreshHeartbeat()
    try formatter()
    try boundedPixelPool()
    print("Virtual camera host: 8 lifecycle / real pixel-buffer tests passed")
  }
}
