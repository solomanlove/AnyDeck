import CoreMedia
import CoreVideo

/// 仅保留格式正确的一帧；超时或时间回退时清除，避免会议继续显示过期内容。
/// 由 CameraDevice 的串行队列独占访问。
final class AnyDeckCameraFrameStore {
  private(set) var latest: CVPixelBuffer?
  private var receivedAt = CMTime.zero

  @discardableResult
  func receive(_ image: CVPixelBuffer, at now: CMTime) -> Bool {
    guard CVPixelBufferGetWidth(image) == AnyDeckCameraContract.width,
          CVPixelBufferGetHeight(image) == AnyDeckCameraContract.height,
          CVPixelBufferGetPixelFormatType(image) == kCVPixelFormatType_32BGRA,
          CVPixelBufferGetIOSurface(image) != nil else { return false }
    latest = image
    receivedAt = now
    return true
  }

  func image(at now: CMTime) -> CVPixelBuffer? {
    let age = CMTimeGetSeconds(CMTimeSubtract(now, receivedAt))
    if !age.isFinite || age < 0 || age > 1 { clear() }
    return latest
  }

  func clear() { latest = nil }
}
