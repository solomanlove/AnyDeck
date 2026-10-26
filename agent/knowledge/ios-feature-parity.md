# iOS 功能对齐：布局、网页调试、录屏与 MCP

## 功能边界

| 功能 | iOS 实现 | 依赖与限制 |
| --- | --- | --- |
| 截图布局分析 | go-ios 截图 + WDA `/source`，Accessibility XML 转共享 `LayoutNode` | 需要已启动且可用的 WDA；原始坐标为 point，按当前截图尺寸换算为像素 |
| 网页调试 | 工具 Tab 打开 Safari，使用 Safari Develop 菜单选择 iPhone 页面 | 需要 iPhone Web Inspector 和 Mac Safari Develop；App 的 WKWebView 需允许检查 |
| 投屏录屏 | USB 使用 `AVCaptureMovieFileOutput`；AirPlay 使用 `AVAssetWriter` 录制 Rust Texture 的 `CVPixelBuffer`；均输出 `.mov` | macOS 侧写入，不传输逐帧数据给 Dart；AirPlay 录制当前视频画面，不包含音频 |
| AI MCP | iOS 设备枚举/详情、截图、UI Tree、WDA 输入、应用和 AFC 文件操作 | WDA 输入需会话在线；文件操作限可访问的 App container；Android 专用 Tool 拒绝 iOS UDID |

## 关键数据流

1. 截图布局页先取得 PNG 像素尺寸，再请求 WDA 实时 `geometry` 和 `/source`。布局服务保留 iOS 属性，并补齐共享画布所需的 `bounds`、`class`、`resource-id` 等字段。Android 截图与 dump 仍并发执行。
2. USB 投屏窗口通过 `anydeck/ios_usb_capture` 的 `startRecording` / `stopRecording` 调用当前 Engine 所持有的 `IosUsbCapture`；AirPlay 窗口通过 `anydeck/rust_texture` 同名方法录制当前 handle 的视频帧。来源切换、Texture 注销和窗口关闭会停止对应录制。
3. MCP 使用设备类型分流；iOS 通用 UI Tool 返回 `coordinateSpace=ios_points`，调用方使用 WDA point 坐标。`ios_*` Tool 只接受在线 iOS UDID。卸载工具仍标记 `isDangerous`。

## 验证与真机回归

- 静态检查：对改动 Dart 文件运行 `flutter analyze --no-pub`，对原生代码运行 macOS Debug 构建。
- 自动测试：`test/ios_capability_route_test.dart`、`test/ios_usb_mirror_service_test.dart`、`test/screenshot_layout_merge_test.dart`、`test/mcp_server_test.dart`。
- 无真机时只能确认解析、路由与编译。真机需补测：横竖屏布局框是否对齐、WDA 断线提示；Safari 页面与可检查 WKWebView 是否出现在 Develop 菜单；USB 录制的音画、AirPlay 视频录制、停止后文件可播放、拔线/窗口关闭回收；MCP 的实际触控、应用及 AFC 文件操作。
