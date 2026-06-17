# 投屏独立窗口行为机制

## 背景

投屏独立窗口由 `MirrorWindowApp` 渲染窗口外壳，由 `MirrorWindowController` 维护 scrcpy 会话、窗口状态和比例适配。窗口内的 `Texture` 必须保持设备画面比例，不能为了铺满窗口直接拉伸，否则会破坏鼠标与触控坐标映射。

## 比例适配

- 启动投屏后，控制器会等待 scrcpy video size 可用，再调用 `MirrorWindowFrameAdapter.fitWindowToAspectRatio()` 修正外层窗口尺寸。
- 启动或横竖屏变化后，控制器会先解除 `windowManager.setAspectRatio(0)`，再做一次窗口贴合，最后用 `windowWidth / (windowWidth / contentAspect + mirrorWindowTopChromeHeight)` 调用 `windowManager.setAspectRatio(...)` 锁定后续拖拽缩放；`mirrorWindowTopChromeHeight` 是自定义标题栏和顶部工具栏的固定高度，不能从当前 `windowHeight - viewerHeight` 动态反推，否则会被已有黑边和原生 frame/content 差异污染。
- 用户手动拖动缩放窗口时，由原生窗口管理器维护比例，不在 Dart 层高频调用 `setWindowFrame` / `setBounds`，避免持续刷 `Resize timed out`。
- 用户拖动缩放结束后会延迟做一次收敛贴合，用于抵消标题栏和工具栏固定高度造成的极端尺寸黑边。
- 投屏窗口设置最小窗口尺寸，避免缩得过小时标题栏右侧按钮和设备标题互相挤压。
- 全屏状态会解除比例锁，退出全屏后重新按当前画面贴合并锁定比例。
- 原生窗口最大化或 macOS 绿色系统全屏不会进入应用沉浸全屏；只有投屏窗口右侧 fullscreen icon 会隐藏自定义标题栏和工具栏。
- 全屏状态不强制修正比例，全屏黑边属于容器大于设备画面时的正常表现。

## 应用投屏模式

- `startApp != null` 表示当前窗口是单 App 投屏窗口。
- 单 App 投屏窗口不再在标题栏展示“打开应用投屏”的 app icon，避免在应用投屏内继续递归打开应用投屏。
- 顶部工具栏在非全屏状态下仍展示，保持返回、Home、截图、录屏、设备设置等快捷控制可用。
- 长按返回键强停前台应用时，停止命令仍以包名执行；如果 `MirrorWindowController.currentForegroundPackage` 已经拿到本地 icon 且 label 非空，则轻提示优先展示应用名，避免把包名直接暴露给用户。
- 长按返回键强停成功后必须清空 `currentForegroundPackage` 并通知 UI，标题栏 app icon 需要立即隐藏；强停失败时保留现有前台应用状态，便于用户重试或重新识别。

## 投屏窗口提示

- 投屏独立窗口内的轻提示统一使用 `lib/app/widget/app_toast.dart` 中的 `AppToast.show(...)`。
- `AppToast` 通过 `OverlayEntry` 渲染在当前窗口居中位置，不依赖 `ScaffoldMessenger`，适合投屏子窗口、设置弹窗返回后的提示、拖拽安装/上传结果、截图/录屏结果、剪贴板发送失败、返回键和音量键长按提示。
- 新增投屏提示时优先按语义选择 `AppToastType.success`、`error`、`warning`、`info`，只有需要兼容旧调用时才使用 `isError` 参数。
