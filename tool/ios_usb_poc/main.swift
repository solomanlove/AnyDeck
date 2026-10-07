import Foundation
import AVFoundation

// 与生产代码复用同一个采集器，输出帧数/尺寸，不落盘屏幕内容。
let arguments = CommandLine.arguments
do { try IosUsbCapture.enableDevices() } catch {
  fputs("USB capture discovery failed: \(error)\n", stderr)
  exit(1)
}
if arguments.count < 2 || arguments[1] == "--list" {
  RunLoop.current.run(until: Date().addingTimeInterval(3))
  for device in IosUsbCapture.devices() {
    let data = try JSONSerialization.data(withJSONObject: IosUsbCapture.describe(device), options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }
  exit(0)
}
let capture = IosUsbCapture()
var failed = false
capture.start(udid: arguments[1]) { error in
  if let error { fputs("\(error.localizedDescription)\n", stderr); failed = true }
}
let duration = arguments.count > 2 ? Double(arguments[2]) ?? 10 : 10
RunLoop.current.run(until: Date().addingTimeInterval(max(1, min(duration, 60))))
let status = capture.diagnostics()
capture.stop()
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
let data = try JSONSerialization.data(withJSONObject: status, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
exit(failed || (status["frames"] as? Int ?? 0) == 0 ? 1 : 0)
