import AVFoundation
import Cocoa
import FlutterMacOS

/// DLNA 仅负责媒体播放；UPnP 发现和控制协议由 Dart 服务处理。
final class DlnaPlayerBridgeService: NSObject, NSWindowDelegate {
  static let shared = DlnaPlayerBridgeService()

  private var player: AVPlayer?
  private var window: NSWindow?
  private var playerView: DlnaPlayerView?
  private var statusObserver: NSKeyValueObservation?
  private var readyObserver: NSKeyValueObservation?
  private var startupTimer: Timer?
  private var reportedItem: ObjectIdentifier?
  private var mediaGeneration = 0
  private var channel: FlutterMethodChannel?
  private var displayName = "AnyDeck DLNA"
  private var loadingText = ""
  private var playbackVolume: Float = 1
  private var playbackMuted = false
  private var isAlwaysOnTop = false
  private var pinControl: DlnaTitlebarPinControl?
  private var pinLabel = "Pin window"
  private var unpinLabel = "Unpin window"

  func setup(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "any_deck/dlna_player", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "playUrl":
        guard let media = call.arguments as? [String: Any],
              let raw = media["url"] as? String,
              let generation = media["generation"] as? Int,
              let url = URL(string: raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
          result(FlutterError(code: "invalid_url", message: "HTTP(S) URL required", details: nil))
          return
        }
        if let text = media["loadingText"] as? String { self.loadingText = text }
        self.play(url, generation: generation, alwaysOnTop: media["alwaysOnTop"] as? Bool ?? false)
        result(nil)
      case "setPinLabels":
        guard let labels = call.arguments as? [String: String],
              let pin = labels["pin"], let unpin = labels["unpin"] else {
          result(FlutterError(code: "invalid_labels", message: "Pin labels required", details: nil))
          return
        }
        self.pinLabel = pin
        self.unpinLabel = unpin
        self.updatePinButton()
        result(nil)
      case "setTitle":
        guard let name = call.arguments as? String, !name.isEmpty else {
          result(FlutterError(code: "invalid_title", message: "DLNA title required", details: nil))
          return
        }
        self.displayName = name
        self.window?.title = name
        result(nil)
      case "setLoadingText":
        guard let text = call.arguments as? String else {
          result(FlutterError(code: "invalid_text", message: "Loading text required", details: nil))
          return
        }
        self.loadingText = text
        self.playerView?.updateLoadingText(text)
        result(nil)
      case "play":
        self.player?.play()
        result(nil)
      case "pause":
        self.player?.pause()
        result(nil)
      case "stop":
        self.stop()
        result(nil)
      case "prepare":
        if let text = call.arguments as? String { self.loadingText = text }
        self.prepare()
        result(nil)
      case "close":
        self.close()
        result(nil)
      case "seek":
        guard let seconds = call.arguments as? Double, seconds.isFinite, seconds >= 0 else {
          result(FlutterError(code: "invalid_position", message: "Invalid seek position", details: nil))
          return
        }
        self.player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        result(nil)
      case "position":
        let seconds = self.player?.currentTime().seconds ?? 0
        result(seconds.isFinite ? seconds : 0)
      case "duration":
        let seconds = self.player?.currentItem?.duration.seconds ?? 0
        result(seconds.isFinite ? seconds : 0)
      case "setVolume":
        guard let volume = call.arguments as? Double else {
          result(FlutterError(code: "invalid_volume", message: "Invalid volume", details: nil))
          return
        }
        self.playbackVolume = Float(max(0, min(1, volume)))
        self.player?.volume = self.playbackVolume
        result(nil)
      case "getVolume":
        result(Double(self.playbackVolume))
      case "setMute":
        guard let muted = call.arguments as? Bool else {
          result(FlutterError(code: "invalid_mute", message: "Invalid mute state", details: nil))
          return
        }
        self.playbackMuted = muted
        self.player?.isMuted = muted
        result(nil)
      case "getMute":
        result(self.playbackMuted)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func play(_ url: URL, generation: Int, alwaysOnTop: Bool) {
    mediaGeneration = generation
    if window == nil {
      let frame = NSRect(x: 0, y: 0, width: 960, height: 540)
      let newWindow = NSWindow(contentRect: frame,
                               styleMask: [.titled, .closable, .miniaturizable, .resizable],
                               backing: .buffered, defer: false)
      newWindow.title = displayName
      newWindow.backgroundColor = .black
      newWindow.isReleasedWhenClosed = false
      newWindow.delegate = self
      newWindow.center()
      // 两种 DLNA 播放窗口共用标题栏图钉，避免遮挡视频画面。
      pinControl = DlnaTitlebarPinControl.install(on: newWindow) { [weak self] in
        self?.toggleAlwaysOnTop()
      }
      let view = DlnaPlayerView(frame: frame)
      newWindow.contentView = view
      playerView = view
      window = newWindow
    }
    isAlwaysOnTop = alwaysOnTop
    window?.level = alwaysOnTop ? .floating : .normal
    updatePinButton()
    let item = AVPlayerItem(url: url)
    let newPlayer = AVPlayer(playerItem: item)
    newPlayer.volume = playbackVolume
    newPlayer.isMuted = playbackMuted
    statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      if item.status == .failed {
        DispatchQueue.main.async {
          self?.reportFailure(item, reason: "item failed")
        }
      }
    }
    startupTimer?.invalidate()
    startupTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self, weak item] _ in
      guard let self = self, let item = item, self.player?.currentItem === item else { return }
      let ready = (self.playerView?.layer as? AVPlayerLayer)?.isReadyForDisplay ?? false
      if !ready { self.reportFailure(item, reason: "first frame timeout") }
    }
    reportedItem = nil
    player?.pause()
    player = newPlayer
    window?.title = displayName
    playerView?.showLoading(loadingText)
    readyObserver = (playerView?.layer as? AVPlayerLayer)?.observe(\.isReadyForDisplay, options: [.new]) { [weak self, weak item] layer, _ in
      guard layer.isReadyForDisplay, let item = item else { return }
      DispatchQueue.main.async {
        guard let self = self, self.player?.currentItem === item else { return }
        self.playerView?.showVideo()
      }
    }
    playerView?.player = newPlayer
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    newPlayer.play()
  }

  private func toggleAlwaysOnTop() {
    isAlwaysOnTop.toggle()
    window?.level = isAlwaysOnTop ? .floating : .normal
    updatePinButton()
    channel?.invokeMethod("pinChanged", arguments: isAlwaysOnTop)
  }

  private func updatePinButton() {
    pinControl?.update(pinned: isAlwaysOnTop, pinLabel: pinLabel, unpinLabel: unpinLabel)
  }

  /// 只上报当前媒体的首次失败；日志保留状态码但不泄露签名 URL。
  private func reportFailure(_ item: AVPlayerItem, reason: String) {
    guard player?.currentItem === item else { return }
    let identity = ObjectIdentifier(item)
    guard reportedItem != identity else { return }
    reportedItem = identity
    startupTimer?.invalidate()
    startupTimer = nil
    let failure = item.error as NSError?
    let event = item.errorLog()?.events.last
    let detail = "\(reason); AVPlayer=\(failure?.domain ?? "unknown")/\(failure?.code ?? -1); HTTP=\(event?.errorStatusCode ?? 0); domain=\(event?.errorDomain ?? "unknown")"
    channel?.invokeMethod("playerFailed", arguments: ["generation": mediaGeneration, "detail": detail])
  }

  private func resetPlayer() {
    startupTimer?.invalidate()
    startupTimer = nil
    statusObserver = nil
    readyObserver = nil
    player?.pause()
    player?.replaceCurrentItem(with: nil)
    player = nil
    playerView?.player = nil
  }

  /// 切视频时保留原窗口和尺寸，释放上一条媒体后显示加载状态。
  private func prepare() {
    resetPlayer()
    playerView?.showLoading(loadingText)
  }

  private func stop() {
    resetPlayer()
    window?.orderOut(nil)
  }

  private func close() {
    if let window = window {
      window.close()
    } else {
      resetPlayer()
    }
  }

  func windowWillClose(_ notification: Notification) {
    resetPlayer()
    window = nil
    pinControl = nil
    isAlwaysOnTop = false
    playerView = nil
    channel?.invokeMethod("playerStopped", arguments: ["generation": mediaGeneration])
  }
}

/// 使用 AVPlayerLayer 播放视频，避免将媒体帧送入 Flutter Widget 树。
private final class DlnaPlayerView: NSView {
  private let loadingBackdrop = NSView()
  private let loadingLabel = NSTextField(labelWithString: "")
  private let loadingOverlay = NSStackView()

  override func makeBackingLayer() -> CALayer { AVPlayerLayer() }
  override var wantsUpdateLayer: Bool { true }

  var player: AVPlayer? {
    get { (layer as? AVPlayerLayer)?.player }
    set { (layer as? AVPlayerLayer)?.player = newValue }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    // 视频保持原比例时，使用黑色填充上下或左右留白。
    (layer as? AVPlayerLayer)?.backgroundColor = NSColor.black.cgColor
    (layer as? AVPlayerLayer)?.videoGravity = .resizeAspect
    let spinner = NSProgressIndicator()
    spinner.style = .spinning
    spinner.controlSize = .large
    spinner.isIndeterminate = true
    spinner.startAnimation(nil)
    loadingLabel.textColor = .white
    loadingLabel.font = .systemFont(ofSize: 16)
    loadingLabel.alignment = .center
    loadingOverlay.orientation = .vertical
    loadingOverlay.alignment = .centerX
    loadingOverlay.spacing = 12
    loadingOverlay.addArrangedSubview(spinner)
    loadingOverlay.addArrangedSubview(loadingLabel)
    loadingBackdrop.wantsLayer = true
    loadingBackdrop.layer?.backgroundColor = NSColor.black.cgColor
    loadingBackdrop.translatesAutoresizingMaskIntoConstraints = false
    loadingOverlay.translatesAutoresizingMaskIntoConstraints = false
    addSubview(loadingBackdrop)
    loadingBackdrop.addSubview(loadingOverlay)
    NSLayoutConstraint.activate([
      loadingBackdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
      loadingBackdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
      loadingBackdrop.topAnchor.constraint(equalTo: topAnchor),
      loadingBackdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
      loadingOverlay.centerXAnchor.constraint(equalTo: loadingBackdrop.centerXAnchor),
      loadingOverlay.centerYAnchor.constraint(equalTo: loadingBackdrop.centerYAnchor),
      loadingOverlay.widthAnchor.constraint(lessThanOrEqualTo: loadingBackdrop.widthAnchor, constant: -40),
    ])
    loadingBackdrop.isHidden = true
  }

  func updateLoadingText(_ text: String) {
    loadingLabel.stringValue = text
    loadingLabel.isHidden = text.isEmpty
  }

  func showLoading(_ text: String) {
    updateLoadingText(text)
    loadingBackdrop.isHidden = false
  }

  func showVideo() { loadingBackdrop.isHidden = true }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// 两种 DLNA 播放窗口共用的标题栏图钉，窗口释放时一并回收。
final class DlnaTitlebarPinControl: NSObject {
  private static var associationKey: UInt8 = 0
  private let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
  private var onTap: (() -> Void)?
  private var closeObserver: NSObjectProtocol?

  static func install(on window: NSWindow, onTap: @escaping () -> Void) -> DlnaTitlebarPinControl {
    if let existing = objc_getAssociatedObject(window, &associationKey) as? DlnaTitlebarPinControl {
      existing.onTap = onTap
      return existing
    }
    let control = DlnaTitlebarPinControl()
    control.onTap = onTap
    control.button.isBordered = false
    control.button.imagePosition = .imageOnly
    control.button.target = control
    control.button.action = #selector(tapped)
    let accessory = NSTitlebarAccessoryViewController()
    accessory.view = control.button
    accessory.layoutAttribute = .right
    window.addTitlebarAccessoryViewController(accessory)
    control.closeObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { [weak control] _ in
      control?.onTap = nil
    }
    objc_setAssociatedObject(window, &associationKey, control, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return control
  }

  func update(pinned: Bool, pinLabel: String, unpinLabel: String) {
    let symbol = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: nil)
    button.image = symbol?.withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
    button.contentTintColor = pinned ? .systemOrange : .secondaryLabelColor
    let label = pinned ? unpinLabel : pinLabel
    button.toolTip = label
    button.setAccessibilityLabel(label)
  }

  @objc private func tapped() { onTap?() }

  deinit {
    if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
  }
}
