# Skill: adb-performance-review (桌面端性能审查)

## 概述
本技能用于评估和审查 AdbManage 作为 Flutter 桌面应用在处理高频、高吞吐场景（如实时屏幕投屏、大数据日志输出、频繁组件树渲染）下的性能损耗。避免出现渲染卡顿（Jank）、主线程阻塞及内存泄漏。

## 核心排查与审查指标

### 1. 投屏渲染优化
- 投屏视频流采用独立的底层 C/C++ 插件（如 `scrcpy_flutter` 自带渲染器）或采用 Texture 共享内存方式更新，严禁在 Dart 层频繁将图片转换为 Base64 或 Uint8List 重新构建 Image 组件。
- 投屏界面应当控制重绘区域，仅对画布区域进行局部更新，避免导致顶层 Scaffold 或状态栏发生全局 rebuild。

### 2. 长列表控制台（Logcat/终端）
- **日志行数硬性限制**：后台在存储和转发 Logcat 消息时，应限制内存中的日志列表长度（例如最大保留 1000 行）。一旦超出上限，使用 FIFO 机制删除旧消息。
- **UI 虚拟化列表**：展示日志时，必须使用 `ListView.builder` 确保界面元素的按需加载和复用，严禁直接使用 SingleChildScrollView 包裹大量 Text 节点。
- **高频更新节流**：对于设备实时输出的控制台日志，UI 更新逻辑建议增加节流（Throttle）或防抖（Debounce）处理（如每 100ms 更新一次 UI 列表，而不是每来一行日志重绘一次）。

### 3. Riverpod 依赖粒度控制
- 避免在大型 Widget 中直接 `ref.watch(appSettingsProvider)`。如果只需要监听其中某一字段（如 `scrcpyAlwaysOnTop`），使用 select 过滤器：
  ```dart
  final alwaysOnTop = ref.watch(appSettingsProvider.select((s) => s.scrcpyAlwaysOnTop));
  ```
- 这样可以保证主题或语言变化时，仅依赖 alwaysOnTop 的 Widget 不会发生不必要的重绘。
