import Foundation
import IOKit

/// AVFoundation 的 uniqueID 是采集端标识，不能假定它等于 usbmux 的 UDID。
/// 旧标识优先精确匹配；UUID 设备仅在物理 USB 与 iOS 屏幕候选都唯一时关联。
enum IosUsbDeviceSelection {
  static func normalize(_ value: String) -> String {
    value.replacingOccurrences(of: "-", with: "").lowercased()
  }

  static func selectID(udid: String, usbSerials: [String],
                       devices: [[String: Any]]) throws -> String? {
    let physical = Set(usbSerials.map(normalize))
    guard physical.contains(normalize(udid)) else { return nil }
    let screens = devices.filter {
      ($0["connected"] as? Bool) == true && ($0["muxed"] as? Bool) == true &&
      ($0["model"] as? String) == "iOS Device" &&
      ($0["manufacturer"] as? String)?.hasPrefix("Apple") == true
    }
    if let exact = screens.first(where: { normalize($0["id"] as? String ?? "") == normalize(udid) }) {
      return exact["id"] as? String
    }
    if screens.isEmpty { return nil }
    guard physical.count == 1 && screens.count == 1 else {
      throw NSError(domain: "IosUsbCapture", code: 4,
        userInfo: [NSLocalizedDescriptionKey: "iosUsbDeviceAmbiguous"])
    }
    return screens[0]["id"] as? String
  }

  /// 直接读取本机 USB 注册表，不把 Wi-Fi 配对设备或电脑摄像头当作 USB iPhone。
  static func connectedSerials() -> [String] {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault,
      IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else { return [] }
    defer { IOObjectRelease(iterator) }
    var serials = Set<String>()
    while case let entry = IOIteratorNext(iterator), entry != 0 {
      defer { IOObjectRelease(entry) }
      var properties: Unmanaged<CFMutableDictionary>?
      guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let values = properties?.takeRetainedValue() as? [String: Any],
            (values["SupportsIPhoneOS"] as? Bool) == true,
            let serial = values["USB Serial Number"] as? String else { continue }
      serials.insert(serial)
    }
    return Array(serials)
  }
}
