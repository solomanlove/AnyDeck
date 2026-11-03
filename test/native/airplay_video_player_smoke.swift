import AVFoundation
import Cocoa
import FlutterMacOS

/// 使用真实 AVPlayer/NSWindow，仅模拟 Flutter 消息传输；不启动 AnyDeck 主程序。
final class PlayerTestMessenger: NSObject, FlutterBinaryMessenger {
  private var handlers: [String: FlutterBinaryMessageHandler] = [:]
  private let codec = FlutterStandardMethodCodec.sharedInstance()
  var failures: [String] = []

  func send(onChannel channel: String, message: Data?) {
    if let message = message {
      let call = codec.decodeMethodCall(message)
      if call.method == "playerFailed" { failures.append(channel); FileHandle.standardError.write(Data("failure=\(String(describing: call.arguments))\n".utf8)) }
    }
  }
  func send(onChannel channel: String, message: Data?, binaryReply: FlutterBinaryReply?) {
    send(onChannel: channel, message: message)
    binaryReply?(codec.encodeSuccessEnvelope(nil))
  }
  func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
    handlers[channel] = handler
    return 1
  }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}

  @discardableResult
  func call(_ channel: String, _ method: String, _ arguments: Any? = nil) -> Any? {
    var reply: Any?
    guard let handler = handlers[channel] else { fatalError("Missing handler: \(channel)") }
    handler(codec.encode(FlutterMethodCall(methodName: method, arguments: arguments))) { data in
      if let data = data { reply = self.codec.decodeEnvelope(data) }
    }
    precondition(!(reply is FlutterError), "Method failed: \(method)")
    return reply
  }
}

@main
struct AirPlayVideoPlayerSmoke {
  static func wait(_ condition: () -> Bool, seconds: Double = 10) {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() && Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    precondition(condition(), "Timed out waiting for native player")
  }

  static func videoReady(_ title: String) -> Bool {
    NSApp.windows.contains { window in
      window.title == title && window.isVisible &&
        ((window.contentView?.layer as? AVPlayerLayer)?.isReadyForDisplay ?? false)
    }
  }

  static func main() {
    precondition(CommandLine.arguments.count == 3, "Pass local HTTP MP4 and HLS URLs")
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.finishLaunching()
    let messenger = PlayerTestMessenger()
    let airplay = "any_deck/airplay_player"
    let dlna = "any_deck/dlna_player"
    DlnaPlayerBridgeService.airplay.setup(messenger: messenger)
    DlnaPlayerBridgeService.shared.setup(messenger: messenger)
    defer {
      messenger.call(airplay, "close")
      messenger.call(dlna, "close")
    }
    messenger.call(airplay, "setMute", true)
    messenger.call(dlna, "setMute", true)
    messenger.call(airplay, "setTitle", "AirPlay native regression")
    messenger.call(dlna, "setTitle", "DLNA isolation regression")
    messenger.call(airplay, "setAppearance", "light")
    messenger.call(dlna, "setAppearance", "light")
    func state() -> [String: Any] {
      messenger.call(airplay, "playbackState") as! [String: Any]
    }
    for (index, url) in CommandLine.arguments.dropFirst().enumerated() {
      messenger.call(airplay, "playUrl", ["url": url, "generation": index + 1,
        "position": 1.0, "rate": 1.0, "loadingText": "Loading"])
      FileHandle.standardError.write(Data("sample \(index): waiting for first frame\n".utf8))
      wait { videoReady("AirPlay native regression") && (state()["position"] as! Double) > 1.2 }
      messenger.call(airplay, "setRate", 0.0)
      wait { (state()["rate"] as! Double) == 0 }
      FileHandle.standardError.write(Data("seeking sample \(index)\n".utf8))
      messenger.call(airplay, "seek", 4.0)
      wait { abs((state()["position"] as! Double) - 4) < 0.3 }
      messenger.call(airplay, "setRate", 1.0)
      wait { (state()["position"] as! Double) > 4.3 }
    }
    messenger.call(dlna, "playUrl", ["url": CommandLine.arguments[1], "generation": 1])
    wait { videoReady("DLNA isolation regression") }
    for title in ["AirPlay native regression", "DLNA isolation regression"] {
      let window = NSApp.windows.first { $0.title == title }!
      precondition(window.appearance?.name == .aqua, "Light theme was not applied to \(title)")
    }
    messenger.call(airplay, "setAppearance", "dark")
    messenger.call(dlna, "setAppearance", "dark")
    for title in ["AirPlay native regression", "DLNA isolation regression"] {
      let window = NSApp.windows.first { $0.title == title }!
      precondition(window.appearance?.name == .darkAqua, "Dark theme was not applied to \(title)")
    }
    messenger.call(airplay, "setAppearance", "system")
    messenger.call(dlna, "setAppearance", "system")
    for title in ["AirPlay native regression", "DLNA isolation regression"] {
      let window = NSApp.windows.first { $0.title == title }!
      precondition(window.appearance == nil, "System theme was not restored for \(title)")
    }
    precondition(messenger.failures.isEmpty, "Native player reported a failure")
    let missing = URL(string: CommandLine.arguments[1])!.deletingLastPathComponent().appendingPathComponent("missing.mp4")
    messenger.call(airplay, "playUrl", ["url": missing.absoluteString, "generation": 3,
      "failureText": "Expected failure"])
    wait { (state()["state"] as! Int) == 2 }
    precondition((state()["rate"] as! Double) == 0, "Failed video kept playing audio")
    messenger.call(airplay, "close")
    precondition(videoReady("DLNA isolation regression"), "AirPlay close stopped DLNA")
    print("PASS: MP4/HLS first frame, progress, initial position, pause/seek/resume, independent DLNA window, failure pauses playback")
  }
}
