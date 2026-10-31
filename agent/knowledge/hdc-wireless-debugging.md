# HarmonyOS HDC 无线调试增强

## 功能边界

HarmonyOS 手机继续使用官方 HDC USB/TCP 通道。AnyDeck 的无线入口负责 USB 自动建链、手动连接、身份绑定、历史地址、USB/TCP 双通道展示和有限退避重连；不会把 Bluetooth、SoftBus 或 UART 伪装成手机无线调试。

UART 仅位于高级折叠区，服务于 OpenHarmony 开发板。Remote HDC Server 默认关闭、默认监听 `127.0.0.1:18710`，用户显式切换后才启动独立前台进程，关闭页面 Provider 或退出应用时回收。

## 数据与逻辑

| 模块 | 职责 |
| --- | --- |
| `core/harmony/wireless/harmony_wireless_models.dart` | IPv4:Port 严格校验、端点与状态模型 |
| `core/providers/modules/harmony_wireless_connection_provider.dart` | SharedPreferences 身份历史、单任务连接、USB 回读 IP 和 3/10/30/60 秒自动重连 |
| `core/harmony/hdc_remote_server.dart` | `hdc -s IP:Port -m` 长进程启动、退出与超时强杀 |
| `features/devices/widgets/harmony_wireless_connection_view.dart` | 手机 USB/TCP 状态、输入粘贴、发现和历史入口 |
| `features/devices/widgets/harmony_wireless_advanced.dart` | Remote HDC Server 与开发板 UART |

普通入口不扫描局域网开放端口，因为 TCP 端口开放不能证明目标为 HDC，也不能确认设备身份。USB 场景读取实时 WLAN IP 后直连；手动地址首次成功后读取硬件 serial 并绑定。最多保存 8 条历史，只自动重连最近一次成功设备；连接互斥，失败最多 5 次，主动断开会抑制本次会话重连。

## 安全与生命周期

- `IP:Port`、监听地址、UART 串口路径均先校验，再作为独立 `Process.start` 参数传入，禁止 Shell 拼接。
- 重连前校验硬件 serial；USB 通道存在时先回读 WLAN IP，避免 DHCP 地址变化继续连接旧主机。
- `bm get -u` 在部分 HDC 版本中会将提示语和 64 位 UDID 分两行输出；身份解析需接受该格式，不能复用带长度限制的设备型号校验。
- Remote HDC Server 监听 `0.0.0.0` 会扩大局域网访问面，UI 明确提示配置防火墙；功能默认关闭。
- USB 仍是 `RegisteredDevice.preferredCommandId` 的最高优先级，不改变投屏、文件、终端等命令路由。

## 验证边界

```bash
flutter analyze --no-pub lib/core/harmony/wireless \
  lib/core/harmony/hdc_remote_server.dart \
  lib/core/providers/modules/harmony_wireless_connection_provider.dart \
  lib/features/devices/widgets/harmony_wireless_connection_view.dart \
  lib/features/devices/widgets/harmony_wireless_advanced.dart

flutter test --no-pub test/harmony_wireless_models_test.dart
flutter test --no-pub test/harmony_tabs_and_wifi_test.dart --plain-name "HDC Wireless Debugging Tests"
```

静态和 Fake CLI 测试不能证明真实手机 ROM 开放端口、AP 隔离、HDC 授权、Remote Server 跨主机访问或 UART 接线可用。需要在真实局域网分别验证 USB+TCP 同时在线、拔线重连、Wi-Fi 切换、休眠恢复、端口关闭、应用退出进程回收和防火墙策略。
