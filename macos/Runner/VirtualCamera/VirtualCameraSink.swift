import Foundation
import CoreMedia
import CoreMediaIO

/// Host 只向固定 UID 的 sink 写帧；通过 source 自定义属性读取下游需求。
protocol VirtualCameraOutput: AnyObject {
  func discover() -> Bool
  func demand() -> Int
  func open() throws
  func write(_ sample: CMSampleBuffer) throws -> Bool
  func close()
}

final class VirtualCameraSink: VirtualCameraOutput {
  private var device: CMIODeviceID = 0
  private var source: CMIOStreamID = 0
  private var sink: CMIOStreamID = 0
  private var queue: CMSimpleQueue?
  private var fullSince: TimeInterval?

  private func address(_ selector: UInt32) -> CMIOObjectPropertyAddress {
    CMIOObjectPropertyAddress(mSelector: selector, mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
                              mElement: UInt32(kCMIOObjectPropertyElementMain))
  }
  private func ids(_ object: CMIOObjectID, _ selector: UInt32) -> [UInt32] {
    var property = address(selector), size: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(object, &property, 0, nil, &size) == noErr,
          size > 0, size <= 4096, size % 4 == 0 else { return [] }
    var values = [UInt32](repeating: 0, count: Int(size) / 4)
    let status = values.withUnsafeMutableBytes {
      CMIOObjectGetPropertyData(object, &property, 0, nil, size, &size, $0.baseAddress)
    }
    return status == noErr ? Array(values.prefix(Int(size) / 4)) : []
  }
  private func string(_ object: CMIOObjectID, _ selector: UInt32) -> String? {
    var property = address(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard CMIOObjectGetPropertyData(object, &property, 0, nil, size, &size, &value) == noErr,
          let value else { return nil }
    return value.takeRetainedValue() as String
  }
  func discover() -> Bool {
    // 已打开时保持 queue 与 ID 成对；失效由 write/demand 错误触发关闭并重新发现。
    if queue != nil { return true }
    device = 0; source = 0; sink = 0
    for candidate in ids(CMIOObjectID(kCMIOObjectSystemObject), UInt32(kCMIOHardwarePropertyDevices)) {
      guard string(candidate, UInt32(kCMIODevicePropertyDeviceUID)) == AnyDeckCameraContract.deviceUID else { continue }
      device = candidate
      for stream in ids(candidate, UInt32(kCMIODevicePropertyStreams)) {
        // stream ID 由 CoreMediaIO 分配，不依赖枚举顺序或 direction 数字。
        let uid = string(stream, UInt32(kCMIOObjectPropertyName))
        if uid == "AnyDeck Camera Source" { source = stream }
        if uid == "AnyDeck Camera Sink" { sink = stream }
      }
      break
    }
    return device != 0 && source != 0 && sink != 0
  }
  func demand() -> Int {
    guard source != 0 else { return 0 }
    let selector = UInt32(0x646d6e64) // dmnd：与 Extension 的 custom property 一致。
    guard let value = string(source, selector), let count = Int(value) else { return 0 }
    return max(0, count)
  }
  func open() throws {
    guard queue == nil else { return }
    guard discover() else { throw VirtualCameraFailure("virtualCameraUnavailable") }
    var retained: Unmanaged<CMSimpleQueue>?
    guard CMIOStreamCopyBufferQueue(sink, nil, nil, &retained) == noErr, let retained else {
      throw VirtualCameraFailure("virtualCameraQueueFailed")
    }
    queue = retained.takeRetainedValue()
    guard CMIODeviceStartStream(device, sink) == noErr else {
      queue = nil
      throw VirtualCameraFailure("virtualCameraQueueFailed")
    }
  }
  func write(_ sample: CMSampleBuffer) throws -> Bool {
    guard let queue else { throw VirtualCameraFailure("virtualCameraQueueFailed") }
    if CMSimpleQueueGetCount(queue) >= CMSimpleQueueGetCapacity(queue) {
      // 保留最新帧在 Rust，满队列直接丢弃本帧，持续堵塞才重建连接。
      let now = ProcessInfo.processInfo.systemUptime
      if let since = fullSince, now - since > 2 { throw VirtualCameraFailure("virtualCameraQueueFailed") }
      if fullSince == nil { fullSince = now }
      return false
    }
    fullSince = nil
    let pointer = Unmanaged.passRetained(sample).toOpaque()
    let status = CMSimpleQueueEnqueue(queue, element: pointer)
    guard status == noErr else {
      Unmanaged<CMSampleBuffer>.fromOpaque(pointer).release()
      throw VirtualCameraFailure("virtualCameraQueueFailed")
    }
    // CMIO 消费队列后释放这份 retain；CMSimpleQueue 自身不管理元素引用。
    return true
  }
  func close() {
    if queue != nil { CMIODeviceStopStream(device, sink) }
    // StopStream 返回后不再消费 host queue；清理尚未转交 CMIO 的 retain。
    if let queue {
      while let pointer = CMSimpleQueueDequeue(queue) {
        Unmanaged<CMSampleBuffer>.fromOpaque(pointer).release()
      }
    }
    queue = nil; fullSince = nil
    device = 0; source = 0; sink = 0
  }
  deinit { close() }
}
