# Skill: adb-multiwindow-sync (多窗口同步梳理)

## 概述
本技能专注于处理 Flutter Desktop 跨 Isolate 状态和窗口的交互同步。多窗口管理依靠 `desktop_multi_window` 实现，此技能提供建立通信通道、数据序列化传递和状态乐观重载的最佳实践。

## 核心同步工作流

### 1. 窗口创建与参数注入
在主窗口（ID 0）拉起子窗口时，采用 JSON 承载初始化状态：
```dart
final window = await DesktopMultiWindow.createWindow(
  jsonEncode({
    'type': 'mirror',
    'deviceId': deviceId,
    'language': currentLanguageCode,
  }),
);
await window.setFrame(const Rect.fromLTWH(0, 0, 800, 600));
await window.show();
```

### 2. 状态更新广播编排 (双向广播)
- **子窗口 -> 主窗口**
  子窗口触发操作（如在子窗口投屏工具栏中点击切换语言），应向主窗口发送方法调用：
  ```dart
  await DesktopMultiWindow.invokeMethod(0, 'update_language', newLanguageCode);
  ```
- **主窗口 -> 其它所有子窗口**
  主窗口的方法接收器拦截此消息后，除了更新主 Isolate 的 Riverpod 状态，还要遍历所有活动的子窗口进行同步：
  ```dart
  final subWindowIds = await DesktopMultiWindow.getAllSubWindowIds();
  for (final id in subWindowIds) {
    await DesktopMultiWindow.invokeMethod(id, 'update_language', newLanguageCode);
  }
  ```

### 3. 数据一致性校验
- 持久化配置（SharedPreferences）更新时，需由执行写操作的 Isolate 广播通知其他 Isolate。
- 严禁在两个窗口中并发向同一个持久化键名写入不同的数据。
- 子窗口的 UI 状态需要在收到 `'update_language'` 或 `'update_themeMode'` 广播后，执行乐观更新（如 `state = state.copyWith(...)`），无需重新读取 SharedPreferences，保证操作即时性。
