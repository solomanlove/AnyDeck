# Skill: adb-multiwindow-sync (多窗口同步梳理)

## 概述
本技能专注于处理 Flutter Desktop 跨 Isolate 状态和窗口的交互同步。多窗口管理依靠 `desktop_multi_window` 实现，此技能提供建立通信通道、数据序列化传递和状态乐观重载的最佳实践。

## 核心同步工作流

### 1. 窗口创建与参数注入
在主窗口拉起子窗口时，使用项目封装传递窗口参数；窗口 ID 由插件动态生成：
```dart
final window = await createAdbManageWindow(
  arguments: {
    'type': 'mirror',
    'deviceId': deviceId,
    'language': currentLanguageCode,
  },
  frame: const Rect.fromLTWH(0, 0, 800, 600),
);
```

### 2. 状态更新广播编排 (双向广播)
- **子窗口 -> 主窗口**
  子窗口触发操作（如切换语言）时，通过主窗口已注册的单向业务通道发送方法调用；不能把主窗口 ID 写死为 `0`：
  ```dart
  const mainChannel = WindowMethodChannel(
    'any_deck/settings_main',
    mode: ChannelMode.unidirectional,
  );
  await mainChannel.invokeMethod('update_language', newLanguageCode);
  ```
- **主窗口 -> 其它所有子窗口**
  主窗口的方法接收器处理消息后，遍历其他活动窗口同步状态：
  ```dart
  final windows = await WindowController.getAll();
  for (final window in windows) {
    if (window.arguments.isNotEmpty) {
      await window.invokeMethod('update_language', newLanguageCode);
    }
  }
  ```

### 3. 数据一致性校验
- 持久化配置（SharedPreferences）更新时，需由执行写操作的 Isolate 广播通知其他 Isolate。
- 严禁在两个窗口中并发向同一个持久化键名写入不同的数据。
- 子窗口的 UI 状态需要在收到 `'update_language'` 或 `'update_themeMode'` 广播后，执行乐观更新（如 `state = state.copyWith(...)`），无需重新读取 SharedPreferences，保证操作即时性。
