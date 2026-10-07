import Foundation

/// 无真机回归：UUID 与 UDID 不同、多设备、错误设备及普通摄像头均有明确边界。
@main
struct SelectionTest {
  static func main() throws {
    func screen(_ id: String) -> [String: Any] {
      ["id": id, "connected": true, "muxed": true,
       "model": "iOS Device", "manufacturer": "Apple Inc."]
    }
    let uuid = "11111111-2222-3333-4444-555555555555"
    let camera: [String: Any] = ["id": "camera", "connected": true,
      "muxed": false, "model": "Mac Camera", "manufacturer": "Apple Inc."]
    func check(_ result: String?, _ expected: String?) {
      precondition(result == expected, "selection mismatch: \(String(describing: result))")
    }
    check(try IosUsbDeviceSelection.selectID(udid: "phone-A", usbSerials: ["phone-A"], devices: [camera, screen(uuid)]), uuid)
    check(try IosUsbDeviceSelection.selectID(udid: "phone-B", usbSerials: ["phone-A"], devices: [screen(uuid)]), nil)
    check(try IosUsbDeviceSelection.selectID(udid: "phone-A", usbSerials: [], devices: [screen(uuid)]), nil)
    check(try IosUsbDeviceSelection.selectID(udid: "phone-A", usbSerials: ["phone-A"], devices: [camera]), nil)
    check(try IosUsbDeviceSelection.selectID(udid: "PHONE-A", usbSerials: ["phone-A", "phone-B"], devices: [screen("phonea"), screen(uuid)]), "phonea")
    for (physical, devices) in [(["phone-A", "phone-B"], [screen(uuid)]), (["phone-A"], [screen(uuid), screen("another")])] {
      do {
        _ = try IosUsbDeviceSelection.selectID(udid: "phone-A", usbSerials: physical, devices: devices)
        preconditionFailure("ambiguous selection must fail")
      } catch { precondition(error.localizedDescription == "iosUsbDeviceAmbiguous") }
    }
    print("7 USB capture identity checks passed")
  }
}
