import Cocoa
import CoreLocation
import CoreWLAN
import FlutterMacOS
import SystemConfiguration

/// 读取宿主机 Wi-Fi 元数据；支持解析手机热点和传统无线路由器名称。
final class HostNetworkBridgeService: NSObject, CLLocationManagerDelegate {
  static let shared = HostNetworkBridgeService()
  private let locationManager = CLLocationManager()
  private let queue = DispatchQueue(label: "any_deck.host_network", qos: .utility)

  override init() {
    super.init()
    locationManager.delegate = self
  }

  func setup(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "any_deck/host_network", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "read":
        let authorized = self.isLocationAuthorized
        // CoreWLAN 可能涉及系统 IPC 或扫描，避免阻塞 Flutter 的主线程。
        self.queue.async {
          let wifi = (CWWiFiClient.shared().interfaces() ?? []).map { interface -> [String: Any] in
            let ssid = self.resolveSSID(interface: interface)
            return [
              "name": interface.interfaceName ?? "",
              "ssid": ssid ?? "",
              "connected": interface.powerOn() &&
                (ssid != nil || interface.activePHYMode().rawValue != 0),
            ]
          }
          let physical = (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []).compactMap {
            interface -> String? in
            let type = SCNetworkInterfaceGetInterfaceType(interface)
            guard type == kSCNetworkInterfaceTypeEthernet || type == kSCNetworkInterfaceTypeIEEE80211 else {
              return nil
            }
            return SCNetworkInterfaceGetBSDName(interface) as String?
          }
          let snapshot: [String: Any] = [
            "wifiInterfaces": wifi,
            "physicalInterfaces": physical,
            "locationAuthorized": authorized,
          ]
          DispatchQueue.main.async { result(snapshot) }
        }
      case "requestWifiAccess":
        let status: CLAuthorizationStatus
        if #available(macOS 11.0, *) {
          status = self.locationManager.authorizationStatus
        } else {
          status = CLLocationManager.authorizationStatus()
        }
        if status == .notDetermined && CLLocationManager.locationServicesEnabled() {
          self.locationManager.requestWhenInUseAuthorization()
        } else if !self.isLocationAuthorized {
          if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
          }
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 解析当前连接的 Wi-Fi 或手机热点名称。
  /// 在 macOS Sonoma/Sequoia 系统上，若未获得定位权限，interface.ssid() 可能返回 nil。
  /// 此时通过匹配信道及信号强度的扫描缓存/已知配置进行解析回退，确保手机热点等名称可正常获取。
  private func resolveSSID(interface: CWInterface) -> String? {
    if let ssid = interface.ssid(), !ssid.isEmpty {
      return ssid
    }

    guard interface.powerOn() else { return nil }
    let currentChannel = interface.wlanChannel()?.channelNumber ?? 0
    guard currentChannel > 0 else { return nil }
    let currentRssi = interface.rssiValue()

    // 优先读取已知网络配置列表辅助精确校验
    let knownProfiles = (interface.configuration()?.networkProfiles.array as? [CWNetworkProfile])?
      .compactMap { $0.ssid }
      .filter { !$0.isEmpty } ?? []

    // 获取缓存的扫描结果或触发扫描
    var candidates: Set<CWNetwork> = interface.cachedScanResults() ?? []
    if candidates.isEmpty || !candidates.contains(where: { $0.wlanChannel?.channelNumber == currentChannel && $0.ssid != nil }) {
      if let scanned = try? interface.scanForNetworks(withSSID: nil) {
        candidates = scanned
      }
    }

    let channelMatches = candidates.filter {
      guard let s = $0.ssid, !s.isEmpty else { return false }
      return $0.wlanChannel?.channelNumber == currentChannel
    }

    if channelMatches.isEmpty {
      return nil
    }

    if channelMatches.count == 1 {
      return channelMatches.first?.ssid
    }

    // 多个匹配时，优先匹配系统已知配置列表，若同在已知列表中则按 RSSI 最接近者排序
    let sorted = channelMatches.sorted { a, b in
      let aKnown = knownProfiles.contains(a.ssid ?? "")
      let bKnown = knownProfiles.contains(b.ssid ?? "")
      if aKnown != bKnown {
        return aKnown
      }
      return abs(a.rssiValue - currentRssi) < abs(b.rssiValue - currentRssi)
    }

    return sorted.first?.ssid
  }

  private var isLocationAuthorized: Bool {
    guard CLLocationManager.locationServicesEnabled() else { return false }
    let status: CLAuthorizationStatus
    if #available(macOS 11.0, *) {
      status = locationManager.authorizationStatus
    } else {
      status = CLLocationManager.authorizationStatus()
    }
    return status == .authorizedAlways || status == .authorized
  }
}
