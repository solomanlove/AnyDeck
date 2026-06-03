---
description: Riverpod 状态管理与多窗口同步规范
globs:
  - "lib/**/*.dart"
alwaysApply: false
---

# Riverpod 状态管理规范

1. **Notifier/AsyncNotifier 优先**
   - 避免使用已经弃用的 legacy `StateNotifier` 或原生的 `StatefulWidget` 进行复杂业务状态管理。
   - 数据更新或有副作用的操作，使用 `Notifier`（同步）或 `AsyncNotifier`（异步）。
   - 通过 `ref.watch` 订阅状态变化；仅在回调函数（如按钮 onPressed）中使用 `ref.read` 执行副作用操作。

2. **异步操作与自动回收 (AutoDispose)**
   - 对于依赖设备连接、Logcat 终端流或特定临时 Panel 的 Provider，声明时优先使用自动回收类型（如 `AutoDisposeNotifier` 或 `AutoDisposeStreamProvider`），保证连接断开或 UI 销毁时，后台 Stream 和资源能及时释放。
   - 超时与错误处理：涉及 ADB 命令执行的 Future/Stream 必须在 Provider 内部做 catch 处理，向 UI 暴露安全的包装对象或 `AsyncValue`。

# 多窗口状态同步规则

1. **跨窗口通讯机制**
   - 本项目通过 `desktop_multi_window` 实现多窗口（主窗口 ID 为 0，子窗口 ID 递增）。
   - 主窗口和子窗口运行在不同的 Isolate 中，内存不共享。
   - 所有全局状态更新（如：系统语言切换、主题变化、投屏全局配置）必须使用 Method Channel 进行双向广播。
   
2. **语言/设置同步示例**
   - 当语言发生变更时，修改者必须通过 `DesktopMultiWindow` 广播新状态：
     - 若当前在**主窗口** (windowId == 0)：广播给所有子窗口。
     - 若当前在**子窗口** (windowId != 0)：发送给主窗口，由主窗口向其他子窗口传播。
   - 必须通过 `DesktopMultiWindow.setMethodHandler` 监听 `'update_language'` 等命令，接收到广播后使用 `ref.read(appSettingsProvider.notifier).setLanguage(..., broadcast: false)` 乐观更新当前 Isolate 的状态。

3. **数据一致性原则**
   - 涉及持久化的设置（如 SharedPreferences），应该由修改窗口直接写入，并由主窗口或子窗口根据更新广播进行即时重载，避免两端本地缓存不一致。
