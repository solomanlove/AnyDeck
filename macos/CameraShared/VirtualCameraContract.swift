import Foundation
import CoreMediaIO

/// 主应用与系统扩展共用的设备标识及格式；升级时保持 UUID 不变。
enum AnyDeckCameraContract {
  static let extensionID = "com.github.anydeck.camera-extension"
  static let hostSigningID = "com.github.anydeck"
  static let deviceUID = "D45CF524-EBB8-42C3-92A4-DA065F0DCE71"
  static let sourceUID = "D45CF524-EBB8-42C3-92A4-DA065F0DCE72"
  static let sinkUID = "D45CF524-EBB8-42C3-92A4-DA065F0DCE73"
  static let width = 1280
  static let height = 720
  static let fps: Int32 = 30
  // CMIO 自定义属性以 NSString 传输 "0"/"1"，挂在 source stream 上。
  @available(macOS 12.3, *)
  static let demandProperty = CMIOExtensionProperty(rawValue: "4cc_dmnd_glob_0000")
}
