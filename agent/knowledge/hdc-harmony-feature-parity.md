# HarmonyOS 功能对齐与真机边界

## 设备与验证范围

- 2026-10-26 使用 USB HDC 设备 `ADA-AL00U`，系统 `OpenHarmony-6.1.0.115` 验证。设备同时存在 TCP 调试连接，测试指定 USB 序列号，避免命令发往错误设备。
- 已通过官方 HarmonyOS Command Line Tools 6.1.1 的 `hvigorw` 编译 `harmony/companion`。这是未签名 HAP；USB 真机安装返回 `9568320 no signature file`，因此尚无设备端采集验收结果。官方工具链位于临时目录，不进入仓库。

## 当前功能状态

| 顺序 | 功能 | 当前结果 | 实现或下一步 |
| --- | --- | --- | --- |
| 1 | 性能 Tab | 已开放；CPU、内存、开机时长、电量与充电状态可读取 | `cat /proc/stat`、`cat /proc/meminfo`、`uptime`、`hidumper -s BatteryService -a -i`；设备不提供的 FPS 不展示 |
| 2 | 控制 Tab 快捷操作 | 通知中心和控制中心 HDC 手势已在真机验证；设备设置、截图、录屏复用既有服务 | 左右状态栏下拉按实时屏幕尺寸计算；录屏只复用系统录屏能力 |
| 3 | 只转发音频 | Companion 原型 HAP 已编译；桌面接收协议已用合成 PCM 测试；真机签名与录制授权待验证 | `AVScreenCapture` 原始码流只转发 `AUDIO_INNER` buffer，视频宽高为 0，mic 关闭；HDC 反向端口转发到 macOS |
| 4 | 摄像头／麦克风 | 麦克风 PCM 与前后摄前台预览原型均已编译；真机授权待验证 | 麦克风独立请求权限，只转发 `AUDIO_MIC` buffer；Camera Kit 会话通过 XComponent 显示，离开页面释放，不向桌面传视频 |
| 5 | 跨应用消息 | HDC shell 未读到跨应用通知内容；普通签名 HAP 未验证 | `SUBSCRIBE_NOTIFICATION` 为 `system_basic` 受限权限，通知订阅扩展面向穿戴设备同步场景；仅用户弹窗不足以获得权限 |

## 性能采集细节

- HarmonyOS 设备的 `/proc/uptime` 返回 permission denied，因此命令回退至 `uptime`；解析 `up h:mm` 或 `up d days, h:mm`。
- `BatteryService` 的 `capacity` 才是百分比；`batteryLevel` 不是百分比。读不到电量时显示 `-`，不伪造 `100%`。
- 这台设备不开放 CPU 频率 sysfs；核心频率不可读时显示 `-`，采样命令不反复探测该目录。
- 不调用 Android 专用的 Rust Direct ADB Socket。采样加运行中保护，避免 HDC 慢响应引发并发轮询。
- 本机 `hidumper -s RenderService -a fpsCount` 返回刷新率计数，不等于当前应用 FPS，因此鸿蒙性能页暂不展示 FPS。

## 媒体与消息的技术边界

1. HDC 的 `hidumper -s AudioPolicyService` 是诊断数据，不能输出可播放 PCM。现有 `hoscrcpy-server` 只建立视频采集链路；`HosRemoteDevice` API 未暴露音频、摄像头或麦克风流。Android `scrcpy-server.jar` 与 ADB 音频路径不适用于 HarmonyOS。
2. 官方 `AVScreenCapture` 示例允许将视频宽高设为 0 以录制纯音频，并以 `OH_ALL_PLAYBACK` 选择设备内音频。实时转发应使用 buffer 回调而非屏幕录制文件；要先编译、签名并在零售设备验证系统授权、后台生命周期及音频焦点。手机通话期间采集可能停止。
3. Camera Kit 和 AudioCapturer 必须由获授权的设备侧应用持有会话。桌面 HDC shell 不等同于相机／麦克风权限，不能从 `hidumper` 输出推断可采集。
4. `hidumper -s DistributedNotificationService -a -a` 在这台设备仅返回服务摘要，没有通知正文。该设备 API version 23；API 22 起提供 `NotificationSubscriberExtensionAbility` 与 `openSubscriptionSettings`，但 `SUBSCRIBE_NOTIFICATION` 是 `system_basic` 受限权限，官方场景要求穿戴设备配对和用户授权。普通应用需先确认 AGC 是否向此应用开放对应 ACL，不能把用户开关等同于权限许可。返回授权结果的 `openSubscriptionSettingsWithResult` 从 API 26 才提供，当前设备不能调用。旧版 `NotificationSubscriber` 文档要求系统级权限，不能把两代 API 混用；未通过前不开放 HarmonyOS 消息 Tab，也不显示 Android 消息。

## 后续最小验收

1. 为 `com.anydeck.harmonycompanion` 申请 HarmonyOS 调试签名与包含本机 UDID 的 Profile，签名安装 HAP；在手机上逐项确认系统录制与麦克风授权。
2. 先验证音频仅含设备内播放、没有画面且不启用 mic；macOS 端播放与停止后无残留 HDC 端口、进程或 AudioQueue。
3. 分别验证后摄、前摄、mic 的首帧／首个 PCM 包、切换和后台回收；摄像头桌面转发需增加编码与传输后再接入控制 Tab。
4. 查询 AGC 是否可向本应用授予 `SUBSCRIBE_NOTIFICATION` ACL。只有获批并完成穿戴设备配对后，才使用当前 API 23 支持的 `openSubscriptionSettings` 进行授权及通知接收实验。

## 官方依据

- [Recording Audio Using AVScreenCapture](https://developer.huawei.com/consumer/en/doc/best-practices/bpta-audio-record-base-on-avscreencapture)
- [AVScreenCapture API](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V13/native__avscreen__capture_8h-V13)
- [Using AVScreenCapture to Record Files](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/using-avscreencapture-for-file)
- [NotificationSubscriber](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V3/notificationsubscriber-0000001054358823-V3)
- [通知订阅扩展能力开发步骤](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ion-subscriber-extension-ability-development-steps)
- [通知订阅扩展能力概述](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/notification-subscriber-extension-ability)
- [相机预配置](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/camera-preconfig-native)
- [HarmonyOS Command Line Tools](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/ide-hvigor-commandline)
