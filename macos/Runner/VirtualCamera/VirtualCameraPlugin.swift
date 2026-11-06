import Cocoa
import FlutterMacOS

/// 所有 Flutter Engine 共用原生协调器；关闭单个窗口不会销毁会议摄像头。
final class VirtualCameraPlugin: NSObject, FlutterPlugin {
  private static let activation = VirtualCameraActivation()
  private static let menu = VirtualCameraMenu()
  private static var labels: [String: String] = [:]
  private static var termination: NSObjectProtocol?
  private let coordinator = VirtualCameraCoordinator.shared
  // lease 与 Engine 关联：不同窗口也无法同时抢占同一台手机的镜头。
  private static var previewLeases: [Int: String] = [:]
  private static var nextLease = 1
  private var leases = Set<Int>()

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = VirtualCameraPlugin()
    let channel = FlutterMethodChannel(name: "anydeck/virtual_camera", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(instance, channel: channel)
    if termination == nil {
      termination = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
        object: nil, queue: .main) { _ in
          VirtualCameraCoordinator.shared.workQueue.sync { VirtualCameraCoordinator.shared.shutdown() }
        }
      menu.selectFront = { front in
        let service = VirtualCameraCoordinator.shared
        service.workQueue.async {
          service.selectFront(front)
          let status = service.snapshot()
          DispatchQueue.main.async { updateMenu(status) }
        }
      }
      menu.stop = {
        let service = VirtualCameraCoordinator.shared
        service.workQueue.async {
          service.configure(nil, enabled: false)
          DispatchQueue.main.async { menu.update(enabled: false, front: false, labels: labels) }
        }
      }
    }
  }
  private static func updateMenu(_ status: [String: Any]) {
    menu.update(enabled: status["enabled"] as? Bool ?? false,
                front: status["front"] as? Bool ?? false, labels: labels)
  }
  private func respond(_ result: @escaping FlutterResult) {
    coordinator.workQueue.async {
      let snapshot = self.coordinator.snapshot(probe: true)
      DispatchQueue.main.async {
        var status = snapshot
        status["supported"] = true
        let ready = snapshot["installed"] as? Bool == true
        status["activation"] = Self.activation.state == "needsReboot" ? "needsReboot" :
          (ready ? "ready" : Self.activation.state)
        if let error = Self.activation.error { status["error"] = error }
        Self.updateMenu(status)
        result(status)
      }
    }
  }
  deinit {
    let tokens = leases
    coordinator.workQueue.async { for token in tokens { Self.previewLeases.removeValue(forKey: token) } }
  }
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "acquirePreview" {
      guard let args = call.arguments as? [String: Any], let device = args["deviceId"] as? String else {
        result(FlutterError(code: "invalid_argument", message: nil, details: nil)); return
      }
      coordinator.workQueue.async {
        let state = self.coordinator.snapshot()
        if state["enabled"] as? Bool == true && state["deviceId"] as? String == device {
          DispatchQueue.main.async { result(FlutterError(code: "virtualCameraPreviewBlocked", message: nil, details: nil)) }
        } else {
          let token = Self.nextLease; Self.nextLease += 1
          Self.previewLeases[token] = device; self.leases.insert(token)
          DispatchQueue.main.async { result(token) }
        }
      }
      return
    }
    if call.method == "releasePreview" {
      let token = (call.arguments as? [String: Any])?["token"] as? Int
      coordinator.workQueue.async {
        if let token, self.leases.remove(token) != nil { Self.previewLeases.removeValue(forKey: token) }
        DispatchQueue.main.async { result(nil) }
      }
      return
    }
    guard #available(macOS 13.0, *) else {
      result(["supported": false, "installed": false, "enabled": false, "activation": "notInstalled"])
      return
    }
    switch call.method {
    case "status": respond(result)
    case "activate": Self.activation.request(activate: true); respond(result)
    case "deactivate":
      coordinator.workQueue.async { self.coordinator.configure(nil, enabled: false) }
      Self.activation.request(activate: false); respond(result)
    case "configure":
      guard let args = call.arguments as? [String: Any], let enabled = args["enabled"] as? Bool else {
        result(FlutterError(code: "invalid_argument", message: "enabled required", details: nil)); return
      }
      var configuration: VirtualCameraCoordinator.Configuration?
      if enabled {
        guard let adb = args["adbPath"] as? String, let device = args["deviceId"] as? String,
              let jar = args["jarPath"] as? String, let front = args["front"] as? Bool,
              !device.isEmpty, !device.hasPrefix("-"), !device.contains("\0"),
              !adb.contains("\0"), !jar.contains("\0"),
              FileManager.default.isExecutableFile(atPath: adb), FileManager.default.fileExists(atPath: jar) else {
          result(FlutterError(code: "invalid_argument", message: "Valid camera configuration required", details: nil)); return
        }
        configuration = .init(adb: adb, device: device, jar: jar, front: front)
      }
      if let labels = args["labels"] as? [String: String] { Self.labels = labels }
      let selected = configuration
      coordinator.workQueue.async {
        if enabled, let selected, Self.previewLeases.values.contains(selected.device) {
          DispatchQueue.main.async { result(FlutterError(code: "virtualCameraPreviewBlocked", message: nil, details: nil)) }
          return
        }
        self.coordinator.configure(selected, enabled: enabled)
        self.respond(result)
      }
    default: result(FlutterMethodNotImplemented)
    }
  }
}
