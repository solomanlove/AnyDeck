import CoreMediaIO
import Foundation

/// 对外 source 提供会议画面，内部 sink 仅接收 AnyDeck 主进程的像素帧。
final class AnyDeckCameraStream: NSObject, CMIOExtensionStreamSource {
  private(set) var stream: CMIOExtensionStream!
  private unowned let camera: AnyDeckCameraDevice
  private let direction: CMIOExtensionStream.Direction
  let formats: [CMIOExtensionStreamFormat]

  init(camera: AnyDeckCameraDevice, direction: CMIOExtensionStream.Direction) {
    self.camera = camera
    self.direction = direction
    let duration = CMTime(value: 1, timescale: AnyDeckCameraContract.fps)
    formats = [CMIOExtensionStreamFormat(formatDescription: camera.format,
      maxFrameDuration: duration, minFrameDuration: duration, validFrameDurations: nil)]
    super.init()
    stream = CMIOExtensionStream(localizedName: direction == .source ? "AnyDeck Camera Source" : "AnyDeck Camera Sink",
      streamID: UUID(uuidString: direction == .source ? AnyDeckCameraContract.sourceUID : AnyDeckCameraContract.sinkUID)!,
      direction: direction, clockType: .hostTime, source: self)
  }

  var availableProperties: Set<CMIOExtensionProperty> {
    if direction == .source { return [.streamActiveFormatIndex, .streamFrameDuration, AnyDeckCameraContract.demandProperty] }
    return [.streamActiveFormatIndex, .streamFrameDuration, .streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup]
  }

  func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
    let result = CMIOExtensionStreamProperties(dictionary: [:])
    result.activeFormatIndex = 0
    result.frameDuration = CMTime(value: 1, timescale: AnyDeckCameraContract.fps)
    if direction == .sink {
      result.sinkBufferQueueSize = 2
      result.sinkBuffersRequiredForStartup = 1
    } else {
      result.setPropertyState(CMIOExtensionPropertyState(value: camera.demand), forProperty: AnyDeckCameraContract.demandProperty)
    }
    return result
  }

  func setStreamProperties(_ properties: CMIOExtensionStreamProperties) throws {
    if let index = properties.activeFormatIndex, index != 0 { throw NSError(domain: "AnyDeckCamera", code: 2) }
    if let duration = properties.frameDuration, CMTimeCompare(duration, CMTime(value: 1, timescale: AnyDeckCameraContract.fps)) != 0 {
      throw NSError(domain: "AnyDeckCamera", code: 3)
    }
  }
  func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
    direction == .source || camera.authorize(client)
  }
  func startStream() throws {
    if direction == .source { camera.changeDemand(1) } else { try camera.startSink() }
  }
  func stopStream() throws {
    if direction == .source { camera.changeDemand(-1) } else { camera.stopSink() }
  }
}
