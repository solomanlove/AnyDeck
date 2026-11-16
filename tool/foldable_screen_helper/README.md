# AnyDeck 折叠屏设备侧 Helper

独立于应用图标 Helper，通过 `app_process` 以 shell 身份请求 `DeviceStateManagerGlobal`。
每台设备以 `/data/local/tmp/anydeck/foldable-screen.lock` 排他文件锁限制单个会话，USB/TCP
两种传输及多个桌面窗口不能同时获得所有权。

## 构建与 host 验证

```bash
python3 script/build_foldable_screen_helper.py
python3 tool/foldable_screen_helper/test_snapshot.py
```

构建使用 Android SDK 36、Build Tools 36.0.0 和 JDK 17，支持 `ANDROID_SDK_ROOT`、
`ANDROID_HOME`、`JAVA_HOME`。产物是包含 `classes.dex` 的
`assets/android/foldable-screen-helper.jar`，最低 Android API 为 31。

## 启动与协议

```bash
adb -s SERIAL push assets/android/foldable-screen-helper.jar /data/local/tmp/anydeck-foldable-screen-helper.jar
adb -s SERIAL shell CLASSPATH=/data/local/tmp/anydeck-foldable-screen-helper.jar app_process / com.anydeck.helper.FoldableScreenHelper
```

stdin、stdout 均为 UTF-8 JSON 行；单行上限 4096 字符。成功启动第一行包含
`{"ready":true,"version":1,"pid":123}`；失败包含 `ready:false`、`code`、`error`。

| stdin | stdout 关键字段 | 含义 |
| --- | --- | --- |
| `{"id":1,"command":"ping"}` | `{"id":1,"ok":true,"ownsRequest":false}` | 心跳续期，不执行 ADB 查询 |
| `{"id":2,"command":"state","state":0}` | `{"id":2,"ok":true,"state":0}` | 请求已提交；宿主还需回读实际屏幕状态及新视频尺寸 |
| `{"id":3,"command":"reset"}` | `{"id":3,"ok":true,"restored":true}` | 仅取消当前 Helper 自己持有的 override |
| `{"id":4,"command":"close"}` | `{"id":4,"ok":true,"restored":false}` | 幂等清理并退出 |

`state` 必须由宿主从该设备能力映射获得，不能把三星的编号当成通用编号。
错误响应包含 `ok:false`、`code`、`error`；`code` 包括 `busy`、`permission`、
`unsupported`、`external_override`、`invalid_command`、`command_failed`。
当前请求被系统取消时可能先收到 `{"event":"canceled","state":0}`；旧请求取消的回调会忽略，
宿主仍应按目标状态匹配事件，避免快速切换期间把新的手动状态清掉。

## 生命周期与所有权边界

- 宿主每 3 秒发送 `ping`；12 秒没有命令、stdin EOF、`close`、正常进程 shutdown
  都会主动调用 `cancelStateRequest()`。watchdog 不轮询 ADB，只读取本地时钟。
- 使用 `FLAG_CANCEL_WHEN_BASE_CHANGES`，用户实际折叠或展开手机时取消手动请求。
- 请求前读取 `dumpsys device_state`，外部 override 活跃时拒绝；清理前再检查 PID，
  外部请求接管后跳过 cancel。无法确认所有权时拒绝操作，错误返回宿主。
- `reset` 未持有请求时直接成功返回 `restored:false`，不会取消其他工具的全局状态。
- Android 的 cancel API 不携带 token；所有权回读和 cancel 之间仍存在外部工具抢占的竞争窗口。
  不支持保证与其他强制切屏工具同时操作；宿主应维持单会话并显示冲突状态。
- `SIGKILL`、系统强杀与设备重启不执行 shutdown hook；部分系统有 sticky requests，
  因此不能承诺所有进程死亡情形自动恢复。宿主需要记录本次持有状态并在重连后核实恢复，
  不应无条件 reset 他人请求。

Hidden API 在 Android/OEM 升级后可能变化。宿主先确认完整双向布局与控制权限，
首次手动请求前通过握手，切换后回读实际主屏。明确不支持时撤销能力并隐藏入口。
当前仅 Samsung SM-F9710 完成双向真机验证；其他型号不能只凭状态编号判断兼容。
反射签名参考 [Android 16 DeviceStateManagerGlobal](https://android.googlesource.com/platform/frameworks/base/+/android-16.0.0_r3/core/java/android/hardware/devicestate/DeviceStateManagerGlobal.java)，
sticky 行为参考 [OverrideRequestController](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/devicestate/OverrideRequestController.java)。

显式真机清理验收（会请求指定状态，随后恢复自动；默认不传参数只输出 SKIP）：

```bash
python3 tool/foldable_screen_helper/test_device.py --device DEVICE_ID --state STATE_ID
```
