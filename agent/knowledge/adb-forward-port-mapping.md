# Knowledge: Android/HarmonyOS 正向端口转发

## 功能与方向

- 正向：电脑 `localhost:<localPort>` → 设备 `localhost:<devicePort>`，用于从电脑访问设备上运行的 TCP 服务。
- 反向：设备 `localhost:<devicePort>` → 电脑 `localhost:<localPort>`，用于设备访问电脑上的开发服务器。原有反向预设和自动应用逻辑保持独立；正向规则目前仅支持手动添加、查看和删除。
- 网络页标题旁的 `?` 弹窗说明两个方向及用途；正向列表仅展示 TCP→TCP 规则，不展示 Web 调试使用的 `localabstract:` socket。

## 命令与数据流

| 操作 | Android ADB | HarmonyOS HDC |
| --- | --- | --- |
| 创建 | `adb -s <id> forward tcp:<local> tcp:<device>` | `hdc -t <id> fport tcp:<local> tcp:<device>` |
| 查询 | `adb -s <id> forward --list` | `hdc -t <id> fport ls`，仅保留 `[Forward]` 行 |
| 删除 | `adb -s <id> forward --remove tcp:<local>` | `hdc -t <id> fport rm tcp:<local> tcp:<device>` |

- UI 仅接受 1–65535 的 TCP 端口；命令层再次校验，并以参数数组传给 `AdbService` / `HdcService`，不经过 Shell 拼接。
- `PortForwardCommand` 负责平台分流；`activeForwardPortsProvider` 单独读取正向列表。添加或删除成功后只刷新正向 Provider，网络页的总刷新按钮同时刷新正向和反向。
- HDC 的 `fport ls` 混合正向与反向，因此先按 `[Forward]` 标记过滤，再解析两个 `tcp:` 节点。删除 HDC 规则时必须同时提供本地和设备端点。

## 验证边界

- `test/harmony_fport_reverse_test.dart` 覆盖 ADB/HDC 列表解析、两平台创建与删除参数、端口范围拦截。
- 需在 Android/HarmonyOS 真机上分别确认正向服务连通性、断线后规则行为，以及与 Web 调试既有 `localabstract:` 映射共存。
