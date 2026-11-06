import Foundation
import CoreMedia

/// 应用级摄像头状态机：只有用户启用且下游有需求时采集；所有状态在串行队列内访问。
final class VirtualCameraCoordinator {
  struct Configuration: Equatable {
    let adb: String
    let device: String
    let jar: String
    let front: Bool
  }
  typealias Factory = (Configuration) throws -> VirtualCameraSession
  static let shared = VirtualCameraCoordinator()
  let workQueue = DispatchQueue(label: "anydeck.virtual-camera", qos: .userInitiated)
  private let output: VirtualCameraOutput
  private let factory: Factory
  private var formatter: VirtualCameraFrameFormatter?
  private var timer: DispatchSourceTimer?
  private let automaticTimer: Bool
  private var timerInterval = 0.25
  private var configuration: Configuration?
  private var session: VirtualCameraSession?
  private var retired: (VirtualCameraSession, TimeInterval)?
  private var enabled = false
  private var installed = false
  private var clients = 0
  private var sent: UInt64 = 0
  private var lastFrame: UInt64 = 0
  private var started: TimeInterval = 0
  private var lastFrameAt: TimeInterval = 0
  private var nextProbe: TimeInterval = 0
  private var idleSince: TimeInterval?
  private var retryAt: TimeInterval = 0
  private var failures = 0
  private var error: String?

  init(output: VirtualCameraOutput = VirtualCameraSink(), automaticTimer: Bool = true, factory: @escaping Factory = {
    try VirtualCameraRustSession(adb: $0.adb, device: $0.device, jar: $0.jar, front: $0.front)
  }) { self.output = output; self.factory = factory; self.automaticTimer = automaticTimer }

  func configure(_ value: Configuration?, enabled: Bool) {
    let now = ProcessInfo.processInfo.systemUptime
    if value != configuration || !enabled { stop(now: now) }
    if let value { configuration = value }
    self.enabled = enabled
    error = nil; failures = 0; retryAt = 0; nextProbe = 0
    if !enabled { clients = 0 }
    if timer == nil && automaticTimer {
      let timer = DispatchSource.makeTimerSource(queue: workQueue)
      timerInterval = 0.25
      timer.schedule(deadline: .now(), repeating: timerInterval, leeway: .milliseconds(3))
      timer.setEventHandler { [weak self] in self?.tick(now: ProcessInfo.processInfo.systemUptime) }
      self.timer = timer; timer.resume()
    }
  }

  func selectFront(_ front: Bool) {
    guard let configuration else { return }
    configure(Configuration(adb: configuration.adb, device: configuration.device,
                            jar: configuration.jar, front: front), enabled: enabled)
  }

  /// 独立 tick 便于测试需求抖动、启动中取消、切镜头与迟到帧，不启动系统摄像头。
  func tick(now: TimeInterval) {
    defer {
      let interval = session == nil ? 0.25 : 1.0 / 30.0
      if interval != timerInterval {
        timerInterval = interval
        timer?.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(3))
      }
    }
    if let (old, deadline) = retired, old.status >= 2 || now >= deadline {
      old.release(); retired = nil
    }
    if !enabled {
      if retired == nil { timer?.cancel(); timer = nil }
      return
    }
    if now >= nextProbe {
      installed = output.discover()
      clients = installed ? output.demand() : 0
      nextProbe = now + 0.5
    }
    if !installed { error = "virtualCameraUnavailable"; stop(now: now); return }
    if clients == 0 {
      if idleSince == nil { idleSince = now }
      if now - (idleSince ?? now) >= 2 { stop(now: now) }
      return
    }
    idleSince = nil
    guard retired == nil, let configuration else { return }
    if session == nil {
      guard now >= retryAt, failures < 3 else { return }
      do {
        try output.open()
        if formatter == nil { formatter = try VirtualCameraFrameFormatter() }
        session = try factory(configuration)
        started = now; lastFrameAt = now; lastFrame = 0; sent = 0; error = nil
      } catch { fail(error, now: now) }
      return
    }
    guard let session else { return }
    if session.status >= 2 { fail(VirtualCameraFailure("cameraDisconnected"), now: now); return }
    let count = session.frames
    if count == lastFrame {
      if now - (lastFrame == 0 ? started : lastFrameAt) > (lastFrame == 0 ? 75 : 3) {
        fail(VirtualCameraFailure("cameraStartFailed"), now: now)
      }
      return
    }
    guard let pixel = session.copyFrame(), let formatter else {
      if now - lastFrameAt > 3 { fail(VirtualCameraFailure("virtualCameraFrameFailed"), now: now) }
      return
    }
    lastFrame = count; lastFrameAt = now
    do {
      let sample = try formatter.sample(pixel, time: CMClockGetTime(CMClockGetHostTimeClock()))
      if try output.write(sample) { sent += 1 }
    } catch { fail(error, now: now) }
  }
  private func fail(_ failure: Error, now: TimeInterval) {
    error = (failure as? VirtualCameraFailure)?.key ?? "cameraStartFailed"
    failures += 1; retryAt = now + 3
    stop(now: now)
  }
  private func stop(now: TimeInterval) {
    if let session {
      session.stop()
      retired = (session, now + 65)
      self.session = nil
    }
    sent = 0; lastFrame = 0
    output.close()
  }
  func snapshot(probe: Bool = false) -> [String: Any] {
    if probe && !enabled { installed = output.discover() }
    return ["enabled": enabled, "installed": installed, "deviceId": configuration?.device ?? "",
            "front": configuration?.front ?? false, "streaming": session != nil && sent > 0,
            "clients": clients, "frames": sent, "error": error ?? ""]
  }
  func shutdown() {
    enabled = false; timer?.cancel(); timer = nil
    session?.stop(); session?.release(); session = nil
    retired?.0.release(); retired = nil; output.close()
  }
  deinit { shutdown() }
}
