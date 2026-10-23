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
  private var channel: FlutterMethodChannel?

  func setup(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "any_deck/dlna_player", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "playUrl":
        guard let raw = call.arguments as? String,
              let url = URL(string: raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
          result(FlutterError(code: "invalid_url", message: "HTTP(S) URL required", details: nil))
          return
        }
        self.play(url)
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
        self.player?.volume = Float(max(0, min(1, volume)))
        result(nil)
      case "getVolume":
        result(Double(self.player?.volume ?? 1))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func play(_ url: URL) {
    if window == nil {
      let frame = NSRect(x: 0, y: 0, width: 960, height: 540)
      let newWindow = NSWindow(contentRect: frame,
                               styleMask: [.titled, .closable, .miniaturizable, .resizable],
                               backing: .buffered, defer: false)
      newWindow.title = "AnyDeck DLNA"
      newWindow.isReleasedWhenClosed = false
      newWindow.delegate = self
      newWindow.center()
      let view = DlnaPlayerView(frame: frame)
      newWindow.contentView = view
      playerView = view
      window = newWindow
    }
    let item = AVPlayerItem(url: url)
    let newPlayer = AVPlayer(playerItem: item)
    statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      if item.status == .failed {
        DispatchQueue.main.async {
          let failure = item.error as NSError?
          let detail = "\(failure?.domain ?? "AVPlayerItem")/\(failure?.code ?? -1): \(item.error?.localizedDescription ?? "Playback failed")"
          self?.window?.title = "AnyDeck DLNA · \(item.error?.localizedDescription ?? "Playback failed")"
          self?.channel?.invokeMethod("playerFailed", arguments: detail)
        }
      }
    }
    player?.pause()
    player = newPlayer
    window?.title = "AnyDeck DLNA"
    playerView?.player = newPlayer
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    newPlayer.play()
  }

  private func stop() {
    statusObserver = nil
    player?.pause()
    player?.replaceCurrentItem(with: nil)
    player = nil
    playerView?.player = nil
    window?.orderOut(nil)
  }

  func windowWillClose(_ notification: Notification) {
    stop()
    channel?.invokeMethod("playerStopped", arguments: nil)
  }
}

/// 使用 AVPlayerLayer 播放视频，避免将媒体帧送入 Flutter Widget 树。
private final class DlnaPlayerView: NSView {
  override func makeBackingLayer() -> CALayer { AVPlayerLayer() }
  override var wantsUpdateLayer: Bool { true }

  var player: AVPlayer? {
    get { (layer as? AVPlayerLayer)?.player }
    set { (layer as? AVPlayerLayer)?.player = newValue }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    (layer as? AVPlayerLayer)?.videoGravity = .resizeAspect
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
