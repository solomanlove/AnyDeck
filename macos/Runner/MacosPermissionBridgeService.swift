import AVFoundation
import Cocoa
import CoreBluetooth
import CoreLocation
import FlutterMacOS
import ServiceManagement
import UserNotifications

/// 主 Engine 的 macOS 权限中心；查询不申请权限，显式用户操作才创建授权请求。
final class MacosPermissionBridgeService: NSObject, CLLocationManagerDelegate, CBPeripheralManagerDelegate {
  static let shared = MacosPermissionBridgeService()
  private lazy var locationManager: CLLocationManager = {
    let manager = CLLocationManager()
    manager.delegate = self
    return manager
  }()
  private var bluetoothManager: CBPeripheralManager?
  private var requests: [String: (token: UUID, result: FlutterResult)] = [:]

  func setup(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "anydeck/macos_permissions", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "permission_unavailable", message: nil, details: nil))
        return
      }
      switch call.method {
      case "readAll": self.readAll(result)
      case "request", "openSettings":
        guard let arguments = call.arguments as? [String: Any],
              let permission = arguments["permission"] as? String,
              MacosPermissionStatus.permissions.contains(permission) else {
          result(FlutterError(code: "invalid_argument", message: "Unknown macOS permission", details: nil))
          return
        }
        if call.method == "request" { self.request(permission, result: result) }
        else { self.openSettings(permission, result: result) }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func readAll(_ result: @escaping FlutterResult) {
    var values = Dictionary(uniqueKeysWithValues: MacosPermissionStatus.permissions.map { ($0, "unknown") })
    values["camera"] = MacosPermissionStatus.camera(AVCaptureDevice.authorizationStatus(for: .video))
    values["bluetooth"] = MacosPermissionStatus.bluetooth(CBManager.authorization)
    values["location"] = MacosPermissionStatus.location(locationManager.authorizationStatus,
      servicesEnabled: CLLocationManager.locationServicesEnabled())
    if #available(macOS 13.0, *) {
      values["loginItems"] = MacosPermissionStatus.loginItems(SMAppService.mainApp.status)
    } else { values["loginItems"] = "manual" }
    let snapshot = MacosPermissionSnapshot(values: values, pending: ["notifications", "cameraExtension"]) {
      result($0)
    }
    // 单项查询迟到也不阻塞整个页面，未返回项保留 unknown。
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { snapshot.finish() }
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        snapshot.update("notifications", status: MacosPermissionStatus.notifications(settings.authorizationStatus))
      }
    }
    VirtualCameraPlugin.readPermissionStatus { snapshot.update("cameraExtension", status: $0) }
  }

  private func request(_ permission: String, result: @escaping FlutterResult) {
    guard MacosPermissionStatus.requestable.contains(permission) else {
      result(FlutterError(code: "permission_not_requestable", message: "Open System Settings for this permission", details: nil))
      return
    }
    guard requests[permission] == nil else {
      result(FlutterError(code: "permission_request_busy", message: nil, details: nil))
      return
    }
    let token = UUID()
    requests[permission] = (token, result)
    // 系统弹窗可持续等待；超时只结束桥接等待，不伪造用户选择。
    DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
      self?.finish(permission, token: token,
        error: FlutterError(code: "permission_timeout", message: nil, details: nil))
    }
    switch permission {
    case "camera":
      guard mayRequest(permission, token: token,
        status: MacosPermissionStatus.camera(AVCaptureDevice.authorizationStatus(for: .video))) else { return }
      AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
        DispatchQueue.main.async { self?.finish(permission, token: token) }
      }
    case "bluetooth":
      guard mayRequest(permission, token: token,
        status: MacosPermissionStatus.bluetooth(CBManager.authorization)) else { return }
      // 创建 manager 只申请 Bluetooth 访问，不扫描、连接或发送广播。
      bluetoothManager = CBPeripheralManager(delegate: self, queue: .main,
        options: [CBPeripheralManagerOptionShowPowerAlertKey: false])
    case "location":
      guard mayRequest(permission, token: token,
        status: MacosPermissionStatus.location(locationManager.authorizationStatus,
          servicesEnabled: CLLocationManager.locationServicesEnabled())) else { return }
      locationManager.requestWhenInUseAuthorization()
    case "notifications":
      UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
        DispatchQueue.main.async {
          guard let self, self.mayRequest(permission, token: token,
            status: MacosPermissionStatus.notifications(settings.authorizationStatus)) else { return }
          UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, error in
            DispatchQueue.main.async {
              self?.finish(permission, token: token, error: error.map {
                FlutterError(code: "permission_request_failed", message: $0.localizedDescription, details: nil)
              })
            }
          }
        }
      }
    default: finish(permission, token: token)
    }
  }

  /// 已拒绝/受限的权限不能重新申请；回传真实状态，交由界面引导打开系统设置。
  private func mayRequest(_ permission: String, token: UUID, status: String) -> Bool {
    guard requests[permission]?.token == token else { return false }
    if status == "notDetermined" { return true }
    finish(permission, token: token, error: status == "authorized" ? nil :
      FlutterError(code: "permission_\(status)", message: nil, details: nil))
    return false
  }

  private func finish(_ permission: String, token: UUID, error: FlutterError? = nil) {
    guard let request = requests[permission], request.token == token else { return }
    requests.removeValue(forKey: permission)
    if permission == "bluetooth" { bluetoothManager = nil }
    request.result(error)
  }

  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    guard peripheral === bluetoothManager, let request = requests["bluetooth"] else { return }
    if CBManager.authorization != .notDetermined || peripheral.state == .poweredOff || peripheral.state == .unsupported {
      finish("bluetooth", token: request.token)
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard let request = requests["location"], manager.authorizationStatus != .notDetermined else { return }
    finish("location", token: request.token)
  }

  private func openSettings(_ permission: String, result: FlutterResult) {
    guard let url = MacosPermissionStatus.settingsURL(for: permission) else {
      result(FlutterError(code: "invalid_argument", message: "Unknown macOS permission", details: nil))
      return
    }
    guard NSWorkspace.shared.open(url) else {
      result(FlutterError(code: "settings_open_failed", message: nil, details: nil))
      return
    }
    result(nil)
  }
}
