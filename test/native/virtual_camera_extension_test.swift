import CoreMedia
import CoreVideo
import Foundation

/// 验证送入系统扩展的真实像素缓冲区约束，不访问任何摄像头。
@main
struct VirtualCameraExtensionTests {
  static func pixel(_ width: Int = 1280, _ height: Int = 720, format: OSType = kCVPixelFormatType_32BGRA) -> CVPixelBuffer {
    var output: CVPixelBuffer?
    let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
    precondition(CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, attrs as CFDictionary, &output) == kCVReturnSuccess)
    return output!
  }

  static func main() {
    let frames = AnyDeckCameraFrameStore()
    let now = CMTime(value: 10, timescale: 1)
    let accepted = pixel()
    precondition(frames.receive(accepted, at: now))
    precondition(frames.image(at: CMTime(value: 109, timescale: 10)) === accepted)
    precondition(!frames.receive(pixel(640, 480), at: now))
    precondition(!frames.receive(pixel(format: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange), at: now))
    precondition(frames.latest === accepted, "错误格式不得覆盖当前合法画面")
    precondition(frames.image(at: CMTime(value: 12, timescale: 1)) == nil)
    precondition(frames.latest == nil, "超时必须释放旧像素缓冲区")
    precondition(frames.receive(accepted, at: now))
    precondition(frames.image(at: CMTime(value: 9, timescale: 1)) == nil)
    precondition(frames.receive(accepted, at: now))
    frames.clear()
    precondition(frames.latest == nil)
    print("Virtual camera extension frame validation: passed")
  }
}
