# Flutter ADB Desktop 技术方案

## 1. 产品定位

`AdbManage` 定位为一个面向 Android 开发和测试场景的 Flutter Desktop 工具，核心目标是把常用 `adb`、`scrcpy`、设备调试、布局辅助、应用管理、文件管理、Logcat 和 Shell 能力做成一个轻量桌面产品。

第一版不追求从零实现投屏协议，而是采用更稳的路线：

```text
Flutter Desktop UI
  -> Dart Process 调用 adb
  -> Dart Process 启动官方 scrcpy
  -> Flutter 管理设备状态、参数模板、快捷操作和工具面板
```

后续如果需要达到 AYA 或 QtScrcpy 的内嵌投屏体验，再引入 native plugin 实现 scrcpy protocol、FFmpeg decode 和 Flutter Texture 渲染。

## 2. 参考项目对比

| 项目 | 技术栈 | 投屏方式 | 适合参考点 | 注意点 |
|---|---|---|---|---|
| AYA | Electron + React + TypeScript + WebCodecs | 内嵌 scrcpy client | ADB 工具箱、Layout Inspector、WebCodecs 解码、control channel 注入 | AGPL-3.0，不直接复用代码 |
| scrcpy | C + SDL + FFmpeg + Android server | 官方低延迟投屏 | scrcpy-server、video/audio/control socket、协议原理 | Flutter 第一版不从零复刻 |
| eScrcpy | Electron + Vue + Node.js + scrcpy + adbkit | scrcpy GUI 管理器，部分版本支持内嵌镜像 | 产品形态、设备管理、参数配置、多设备、快捷控制栏 | 部分内嵌镜像能力依赖 proprietary package，不直接复用 |
| QtScrcpy | C++ + Qt + FFmpeg + OpenGL | 原生内嵌投屏 | 低延迟渲染、键鼠映射、多设备控制、native pipeline | 开发成本高，适合后期 native 插件参考 |

推荐组合：

```text
产品形态参考 eScrcpy
ADB 工具能力参考 AYA
内嵌投屏演进参考 QtScrcpy
底层协议以官方 scrcpy 文档和源码为准
```

## 3. 推荐技术栈

| 层级 | 技术选择 | 说明 |
|---|---|---|
| 主语言 | Dart / Flutter Desktop | 负责跨平台桌面 UI、状态展示、交互面板 |
| 状态管理 | Riverpod | 管理设备列表、当前设备、进程、Logcat、Shell、scrcpy session 生命周期 |
| 路由 | go_router | 管理页面跳转和模块入口 |
| ADB 调用 | Dart `Process.run` / `Process.start` | 轻量封装 `adb` 命令 |
| 投屏 MVP | external scrcpy | 通过 `Process.start('scrcpy', args)` 启动官方 scrcpy |
| 后期内嵌投屏 | C++ native plugin + FFmpeg + Flutter Texture | 实现低延迟内嵌画面渲染 |
| 本地配置 | shared_preferences 或 Hive | 保存 adb 路径、scrcpy 参数模板、设备偏好 |
| 文件拖拽 | desktop_drop | 支持 APK 拖拽安装、文件 push |
| Shell / Logcat | Stream + terminal widget | 实时输出、过滤、暂停、导出 |

不建议第一版使用纯 H5 / Electron 方案，因为内存占用偏高；也不建议纯 C++/Qt 全写，因为 UI 迭代和业务工具开发效率低。Python 更适合脚本原型，不适合作为正式桌面产品主语言。

## 4. 总体架构

```text
lib/
  app/
    router/
    theme/
  core/
    adb/
      adb_service.dart
      adb_result.dart
      adb_device.dart
    scrcpy/
      scrcpy_service.dart
      scrcpy_session.dart
      scrcpy_launch_options.dart
    config/
    process/
  features/
    devices/
    layout_helper/
    device_actions/
    apps/
    files/
    logcat/
    shell/
    performance/
    settings/
```

核心原则：

1. UI 不直接拼接命令，统一走 service。
2. 长生命周期任务使用 session 表示，例如 `ScrcpySession`、`LogcatSession`、`ShellSession`。
3. 所有 `Process`、`StreamSubscription`、`Timer` 都由 Riverpod provider 生命周期托管。
4. 命令失败必须返回明确错误，UI 给出失败提示，不静默吞掉。

## 5. 核心服务接口

### 5.1 AdbService

```dart
class AdbService {
  Future<List<AdbDevice>> listDevices();

  Stream<List<AdbDevice>> trackDevices();

  Future<AdbResult> run(List<String> args);

  Future<AdbResult> shell(String deviceId, String command);
}
```

职责：

| 方法 | 说明 |
|---|---|
| `listDevices` | 执行 `adb devices -l` 并解析设备列表 |
| `trackDevices` | 轮询或基于 `adb track-devices` 监听设备变化 |
| `run` | 执行普通 adb 命令 |
| `shell` | 执行 `adb -s <deviceId> shell <command>` |

### 5.2 ScrcpyService

```dart
class ScrcpyService {
  Future<ScrcpySession> start({
    required String deviceId,
    required ScrcpyLaunchOptions options,
  });

  Future<void> stop(String sessionId);
}
```

第一版只负责启动外部 scrcpy：

```bash
scrcpy -s <deviceId> --max-size 1920 --video-bit-rate 8M
```

### 5.3 DeviceActionService

```dart
class DeviceActionService {
  Future<void> connect(String address);
  Future<void> disconnect(String address);
  Future<void> inputText(String deviceId, String text);
  Future<void> toggleLayoutBounds(String deviceId, bool enabled);
  Future<void> standby(String deviceId);
  Future<void> setWifi(String deviceId, bool enabled);
  Future<void> setMobileData(String deviceId, bool enabled);
}
```

## 6. 投屏实现原理

### 6.1 官方 scrcpy 架构

scrcpy 由两部分组成：

```text
Host client
  -> push scrcpy-server 到 Android
  -> adb reverse / adb forward 建立 tunnel
  -> 启动 Android 端 server
  -> 接收 video/audio/control socket
```

Android 端 server 负责：

| 通道 | 作用 |
|---|---|
| video socket | 发送 H.264 / H.265 / AV1 屏幕编码流 |
| audio socket | 发送 Opus / AAC / FLAC / raw 音频流 |
| control socket | 接收鼠标、键盘、滚轮、剪贴板、亮屏息屏等控制消息 |

### 6.2 AYA 的内嵌投屏原理

AYA 不是简单打开外部 scrcpy 窗口，而是在 Electron 中实现了一个 scrcpy client：

```text
Electron / React UI
  -> Node net.Server
  -> adb reverse
  -> Android scrcpy-server 连接回 host
  -> WebCodecsVideoDecoder 解码 H.264
  -> HTMLVideoElement 显示画面
  -> ScrcpyControlMessageWriter 注入触控和键盘事件
```

关键点：

| 能力 | AYA 实现方式 |
|---|---|
| 视频解码 | WebCodecs |
| 视频渲染 | HTMLVideoElement |
| 触控注入 | control socket + scrcpy control message |
| 键盘注入 | keydown / keyup 转 Android key event |
| 音频播放 | Opus decode + PCM player |
| 录制 | 记录 video/audio packet 后 mux |

### 6.3 QtScrcpy 的 native pipeline

QtScrcpy 更接近原生高性能方案：

```text
scrcpy-server
  -> ADB socket
  -> H.264 / H.265 stream
  -> FFmpeg decode
  -> OpenGL render
  -> keyboard / mouse event
  -> control socket
```

Flutter 后期如果做内嵌投屏，建议参考这个路线：

```text
Flutter UI
  -> MethodChannel / FFI
  -> C++ native plugin
  -> scrcpy protocol
  -> FFmpeg decode
  -> Flutter Texture
  -> control channel input injection
```

不建议纯 Dart 解码视频，性能和延迟都不适合长期产品。

## 7. ADB 功能模块

### 7.1 Layout Helper

图片中的 Layout Helper 功能可以通过 adb shell 实现：

| 功能 | 命令 |
|---|---|
| Show layout bounds | `setprop debug.layout true/false` |
| Dark mode | `cmd uimode night yes/no` |
| Font scale | `settings put system font_scale 1.20` |
| Display size | `wm size 720x1280` / `wm size reset` |
| Window animation scale | `settings put global window_animation_scale 0.5` |
| Transition animation scale | `settings put global transition_animation_scale 0.5` |
| Animator duration | `settings put global animator_duration_scale 0.5` |
| HWUI Rendering Bars | `setprop debug.hwui.profile visual_bars` |
| Profile GPU Rendering | `settings put global debug_hwui_profile true` |

示例：

```bash
adb shell setprop debug.layout true
adb shell cmd uimode night yes
adb shell settings put system font_scale 1.20
adb shell wm size 720x1280
adb shell settings put global window_animation_scale 0.5
```

注意：`setprop debug.layout`、`debug.hwui.profile` 在部分 ROM 上可能需要重启当前 App 或 SystemUI 才能完全刷新。

### 7.2 Device 快捷菜单

| 功能 | 命令 |
|---|---|
| Connect | `adb connect <ip>:<port>` |
| Disconnect | `adb disconnect <ip>:<port>` |
| Input Text | `adb shell input text "hello"` |
| Toggle Layout Bounds | `adb shell setprop debug.layout true/false` |
| Stand By | `adb shell input keyevent KEYCODE_POWER` |
| Enable Offline Mode | `adb shell cmd connectivity airplane-mode enable` |
| Disable Offline Mode | `adb shell cmd connectivity airplane-mode disable` |
| Enable Wifi | `adb shell svc wifi enable` |
| Disable Wifi | `adb shell svc wifi disable` |
| Enable Mobile Data | `adb shell svc data enable` |
| Disable Mobile Data | `adb shell svc data disable` |
| Enable TalkBack | 写入 `enabled_accessibility_services` |
| Disable TalkBack | `settings put secure accessibility_enabled 0` |

兼容性说明：

1. Android 10 以后 Wi-Fi / Mobile Data 可能被 ROM 限制。
2. Airplane Mode 在不同 Android 版本上命令有差异，需要 fallback。
3. TalkBack 服务名在不同系统上可能不同，不能写死为唯一包名。

### 7.3 应用管理

| 功能 | 命令 |
|---|---|
| 安装 APK | `adb install -r <apk>` |
| 卸载应用 | `adb uninstall <package>` |
| 启动应用 | `adb shell monkey -p <package> 1` |
| 停止应用 | `adb shell am force-stop <package>` |
| 清除数据 | `adb shell pm clear <package>` |
| 列出应用 | `adb shell pm list packages` |

### 7.4 文件管理

| 功能 | 命令 |
|---|---|
| 上传文件 | `adb push <local> <remote>` |
| 下载文件 | `adb pull <remote> <local>` |
| 删除文件 | `adb shell rm <path>` |
| 创建目录 | `adb shell mkdir -p <path>` |
| 查看目录 | `adb shell ls -la <path>` |

### 7.5 Logcat

使用长连接进程读取 stdout：

```bash
adb -s <deviceId> logcat
```

建议支持：

| 功能 | 说明 |
|---|---|
| 实时日志 | Stream 渲染 |
| 过滤 | tag / package / level / keyword |
| 暂停 | UI 暂停消费，不一定杀进程 |
| 清空 | 清空前端 buffer |
| 导出 | 保存当前 buffer 到文件 |

### 7.6 Shell

第一版可以启动交互式 shell：

```bash
adb -s <deviceId> shell
```

Flutter 侧使用 terminal widget 绑定 stdin / stdout / stderr。

## 8. 状态管理方案

推荐使用 Riverpod，不建议长期使用 GetX 作为主状态管理。

| 方案 | 是否可用 | 适合场景 | 结论 |
|---|---|---|---|
| GetX | 可用 | 快速原型、小工具 | 后期全局状态和进程生命周期容易失控 |
| Riverpod | 推荐 | 多设备、进程、Stream、可取消任务 | 适合长期维护 |
| Provider | 可用 | 简单状态 | 表达力弱于 Riverpod |
| Bloc | 可用 | 强流程业务 | 写法偏重 |

Riverpod 适合本项目的原因：

1. 设备列表可以用 `StreamProvider`。
2. `scrcpy session` 可以用 `AutoDisposeAsyncNotifier` 管理进程生命周期。
3. Logcat / Shell 都是长连接 stream，适合 provider 自动释放。
4. 测试时不依赖全局单例，便于 mock。

示例：

```dart
final adbServiceProvider = Provider<AdbService>((ref) {
  return AdbService();
});

final devicesProvider = StreamProvider<List<AdbDevice>>((ref) {
  final adb = ref.watch(adbServiceProvider);
  return adb.trackDevices();
});

final selectedDeviceProvider = StateProvider<AdbDevice?>((ref) {
  return null;
});
```

scrcpy session 示例：

```dart
final scrcpySessionProvider =
    AutoDisposeAsyncNotifierProvider<ScrcpySessionNotifier, ScrcpySession?>(
  ScrcpySessionNotifier.new,
);

class ScrcpySessionNotifier extends AutoDisposeAsyncNotifier<ScrcpySession?> {
  Process? _process;

  @override
  Future<ScrcpySession?> build() async {
    ref.onDispose(() {
      _process?.kill();
    });
    return null;
  }

  Future<void> start(String deviceId) async {
    _process = await Process.start('scrcpy', ['-s', deviceId]);
    state = AsyncData(ScrcpySession(deviceId: deviceId));
  }

  Future<void> stop() async {
    _process?.kill();
    _process = null;
    state = const AsyncData(null);
  }
}
```

## 9. MVP 功能清单

第一版建议优先实现稳定可用的工具链，不做内嵌投屏。

| 优先级 | 模块 | 功能 |
|---|---|---|
| P0 | 设备管理 | USB 设备列表、当前设备选择、刷新、连接状态 |
| P0 | scrcpy 启动器 | 外部启动 scrcpy、参数模板、停止 session |
| P0 | Device 快捷菜单 | Connect、Disconnect、Input Text、Stand By、Toggle Layout Bounds |
| P0 | Layout Helper | layout bounds、dark mode、font scale、display size、animation scale |
| P1 | App 管理 | 安装、卸载、启动、停止、清数据、应用列表 |
| P1 | Logcat | 实时日志、过滤、暂停、清空、导出 |
| P1 | Shell | 交互式 adb shell |
| P2 | File 管理 | push、pull、删除、目录浏览 |
| P2 | Performance | CPU、memory、FPS、battery 基础信息 |
| P3 | 多设备批量操作 | 批量执行命令、群控预研 |

## 10. 演进路线

### 阶段 1：Flutter ADB Toolbox

目标：先做出可用桌面工具。

```text
Flutter Desktop
  -> adb CLI
  -> external scrcpy
  -> Layout Helper
  -> Device Actions
  -> App / File / Logcat / Shell
```

### 阶段 2：scrcpy 参数管理器

目标：做成 eScrcpy 风格的投屏管理器。

功能：

1. 分辨率、码率、帧率、窗口置顶、录屏参数模板。
2. 每台设备保存独立配置。
3. 多设备同时启动 scrcpy。
4. 快捷控制栏。

### 阶段 3：内嵌投屏

目标：实现 AYA / QtScrcpy 类似体验。

```text
C++ native plugin
  -> push / start scrcpy-server
  -> adb reverse / forward
  -> parse video/audio/control socket
  -> FFmpeg decode
  -> Flutter Texture render
  -> pointer / keyboard -> control message
```

### 阶段 4：高级控制

目标：增强测试和自动化能力。

功能：

1. 键鼠映射。
2. 多设备群控。
3. 操作录制和回放。
4. 常用测试脚本模板。

## 11. 风险点与兼容性

| 风险 | 说明 | 处理策略 |
|---|---|---|
| ADB 路径不可用 | 用户未安装 Android SDK 或 adb 不在 PATH | 设置页支持自定义 adb path |
| scrcpy 不存在 | 用户未安装 scrcpy | 设置页检测并提示安装 |
| ROM 限制命令 | Wi-Fi、Mobile Data、Airplane Mode、TalkBack 可能被限制 | 命令失败时显示错误，提供 fallback |
| 多设备冲突 | adb 命令未指定 `-s` 会执行失败 | 所有设备命令强制带 deviceId |
| 长连接泄漏 | Logcat、Shell、scrcpy 进程未释放 | Riverpod `ref.onDispose()` 统一释放 |
| 内嵌投屏复杂 | 协议、解码、渲染、输入注入成本高 | 第一版只 external scrcpy，后期单独研发 native plugin |
| 开源许可证 | AYA 是 AGPL-3.0，eScrcpy 部分能力有 proprietary 依赖 | 只参考产品和架构，不直接复用源码 |

## 12. 开发默认约束

1. 第一版只创建 Flutter Desktop 产品，不做 Android mobile app。
2. 不直接复用 AYA、eScrcpy、QtScrcpy 源码。
3. 投屏第一版只调用官方 `scrcpy`。
4. 所有 adb shell 命令都必须通过统一 service 执行。
5. 所有长生命周期进程都必须有明确 stop / dispose。
6. UI 上对高风险命令做确认，例如清除应用数据、卸载应用、重置分辨率。
7. 不把 ROM 不兼容当作崩溃处理，应该以命令失败提示呈现。

