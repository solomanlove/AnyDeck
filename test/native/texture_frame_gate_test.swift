import Foundation

/// 原生单元测试只调用实际帧调度策略，不创建窗口或启动 Flutter Engine。
@main
struct TextureFrameGateTest {
  static func main() {
    var gate = TextureFrameGate()
    precondition(gate.shouldNotify(1, visible: true))
    for _ in 0..<600 { precondition(!gate.shouldNotify(1, visible: true)) }
    precondition(gate.shouldNotify(2, visible: true))
    precondition(!gate.shouldNotify(3, visible: false))
    precondition(gate.shouldNotify(3, visible: true))
    precondition(!gate.shouldNotify(3, visible: true))
    precondition(gate.shouldNotify(nil, visible: true))
    precondition(TextureFrameGate.interval(hasTextures: true, visible: false, recording: false) == nil)
    precondition(TextureFrameGate.interval(hasTextures: false, visible: true, recording: true) == nil)
    precondition(TextureFrameGate.interval(hasTextures: true, visible: true, recording: false) == 1.0 / 60.0)
    precondition(TextureFrameGate.interval(hasTextures: true, visible: false, recording: true) == 1.0 / 30.0)
    print("TextureFrameGate: 停帧、隐藏恢复、兼容回退及录制调度通过")
  }
}
