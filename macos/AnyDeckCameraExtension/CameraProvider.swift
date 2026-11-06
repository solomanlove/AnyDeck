import CoreMediaIO
import Foundation

/// 发布一个摄像头设备；系统负责视频客户端的隐私授权。
final class AnyDeckCameraProvider: NSObject, CMIOExtensionProviderSource {
  private(set) var provider: CMIOExtensionProvider!
  private let camera: AnyDeckCameraDevice

  init(camera: AnyDeckCameraDevice) throws {
    self.camera = camera
    super.init()
    provider = CMIOExtensionProvider(source: self, clientQueue: nil)
    try provider.addDevice(camera.device)
  }

  var availableProperties: Set<CMIOExtensionProperty> { [.providerManufacturer] }
  func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
    let result = CMIOExtensionProviderProperties(dictionary: [:])
    result.manufacturer = "AnyDeck"
    return result
  }
  func setProviderProperties(_ properties: CMIOExtensionProviderProperties) throws {}
  func connect(to client: CMIOExtensionClient) throws {}
  func disconnect(from client: CMIOExtensionClient) { camera.disconnect(client) }
}
