import CoreMedia
import CoreVideo
import CoreImage

/// 统一固定视频格式；等比留边，保证切换不同手机/镜头时会议应用不必重新选择设备。
final class VirtualCameraFrameFormatter {
  private let context = CIContext(options: [.cacheIntermediates: false])
  private var pool: CVPixelBufferPool?
  private var format: CMVideoFormatDescription?

  init() throws {
    let attributes: [String: Any] = [
      kCVPixelBufferWidthKey as String: AnyDeckCameraContract.width,
      kCVPixelBufferHeightKey as String: AnyDeckCameraContract.height,
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
    guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess else {
      throw VirtualCameraFailure("virtualCameraFrameFailed")
    }
  }

  func sample(_ input: CVPixelBuffer, time: CMTime) throws -> CMSampleBuffer {
    var pixel = input
    if CVPixelBufferGetWidth(input) != AnyDeckCameraContract.width ||
        CVPixelBufferGetHeight(input) != AnyDeckCameraContract.height ||
        CVPixelBufferGetPixelFormatType(input) != kCVPixelFormatType_32BGRA {
      var output: CVPixelBuffer?
      let limit = [kCVPixelBufferPoolAllocationThresholdKey as String: 6] as CFDictionary
      guard let pool, CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, limit, &output) == 0,
            let output else { throw VirtualCameraFailure("virtualCameraFrameFailed") }
      let image = CIImage(cvPixelBuffer: input)
      let width = CGFloat(AnyDeckCameraContract.width), height = CGFloat(AnyDeckCameraContract.height)
      let scale = min(width / image.extent.width, height / image.extent.height)
      let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        .transformed(by: CGAffineTransform(translationX: (width - image.extent.width * scale) / 2,
                                          y: (height - image.extent.height * scale) / 2))
      let bounds = CGRect(x: 0, y: 0, width: width, height: height)
      let background = CIImage(color: .black).cropped(to: bounds)
      context.render(scaled.composited(over: background), to: output, bounds: bounds,
                     colorSpace: CGColorSpaceCreateDeviceRGB())
      pixel = output
    }
    if format == nil {
      guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixel,
                                                         formatDescriptionOut: &format) == noErr else {
        throw VirtualCameraFailure("virtualCameraFrameFailed")
      }
    }
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                    presentationTimeStamp: time, decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    guard let format, CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixel,
      formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
      let sample else { throw VirtualCameraFailure("virtualCameraFrameFailed") }
    return sample
  }
}
