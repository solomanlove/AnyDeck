import CoreMediaIO
import Foundation

// 系统独立启动此进程；手机采集和 ADB 只在宿主应用内运行。
let cameraProvider = try AnyDeckCameraProvider(camera: AnyDeckCameraDevice(registerStreams: true))
CMIOExtensionProvider.startService(provider: cameraProvider.provider)
CFRunLoopRun()
