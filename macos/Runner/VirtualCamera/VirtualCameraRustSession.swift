import Foundation
import CoreVideo

/// 原生会话接口使会议生命周期可独立测试，不依赖 Flutter 页面或真实镜头。
protocol VirtualCameraSession: AnyObject {
  var status: UInt8 { get }
  var frames: UInt64 { get }
  func copyFrame() -> CVPixelBuffer?
  func stop()
  func release()
}

/// 复用现有 Rust ABI；句柄仅由协调器串行访问，dylib 在进程生命周期内常驻。
final class VirtualCameraRustSession: VirtualCameraSession {
  private typealias Start = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>, UInt8) -> UInt64
  private typealias Status = @convention(c) (UInt64) -> UInt8
  private typealias Frames = @convention(c) (UInt64) -> UInt64
  private typealias Copy = @convention(c) (UInt64) -> UnsafeMutableRawPointer?
  private typealias Action = @convention(c) (UInt64) -> Void
  private var handle: UInt64
  private let readStatus: Status
  private let readFrames: Frames
  private let copy: Copy
  private let stopSession: Action
  private let releaseSession: Action
  // 不 dlclose：停止中的 Rust worker 仍可能执行库内代码。
  private static let library: UnsafeMutableRawPointer? = {
    if let path = ProcessInfo.processInfo.environment["ANYDECK_DEVICE_BRIDGE"],
       let library = dlopen(path, RTLD_NOW | RTLD_GLOBAL) { return library }
    guard let path = Bundle.main.privateFrameworksPath else { return nil }
    return dlopen(path + "/libanydeck_device_bridge.dylib", RTLD_NOW | RTLD_GLOBAL)
  }()

  init(adb: String, device: String, jar: String, front: Bool) throws {
    guard let library = Self.library,
      let a = dlsym(library, "anydeck_start"), let b = dlsym(library, "anydeck_status"),
      let c = dlsym(library, "anydeck_decoded_frames"), let d = dlsym(library, "anydeck_copy_pixel_buffer"),
      let e = dlsym(library, "anydeck_stop"), let f = dlsym(library, "anydeck_release") else {
      throw VirtualCameraFailure("virtualCameraUnavailable")
    }
    readStatus = unsafeBitCast(b, to: Status.self)
    readFrames = unsafeBitCast(c, to: Frames.self)
    copy = unsafeBitCast(d, to: Copy.self)
    stopSession = unsafeBitCast(e, to: Action.self)
    releaseSession = unsafeBitCast(f, to: Action.self)
    let start = unsafeBitCast(a, to: Start.self)
    handle = adb.withCString { a in device.withCString { b in jar.withCString { c in
      start(a, b, c, front ? 3 : 0)
    } } }
    guard handle != 0 else { throw VirtualCameraFailure("cameraStartFailed") }
  }
  var status: UInt8 { handle == 0 ? 2 : readStatus(handle) }
  var frames: UInt64 { handle == 0 ? 0 : readFrames(handle) }
  func copyFrame() -> CVPixelBuffer? {
    guard handle != 0, let pointer = copy(handle) else { return nil }
    return Unmanaged<CVPixelBuffer>.fromOpaque(pointer).takeRetainedValue()
  }
  func stop() { if handle != 0 { stopSession(handle) } }
  func release() { if handle != 0 { releaseSession(handle); handle = 0 } }
  deinit { release() }
}

/// 对外仅传递本地化 key，底层错误信息留在本机日志。
struct VirtualCameraFailure: Error {
  let key: String
  init(_ key: String) { self.key = key }
}
