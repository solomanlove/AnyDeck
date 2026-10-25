# HarmonyOS 功能对齐与真机边界

## 设备与验证范围

- 2026-10-26 使用 USB HDC 设备 `ADA-AL00U`，系统 `OpenHarmony-6.1.0.115` 验证。设备同时存在 TCP 调试连接，测试指定 USB 序列号，避免命令发往错误设备。
- 已通过官方 HarmonyOS Command Line Tools 6.1.1 的 `hvigorw` 编译 `harmony/companion`，用专用调试证书与包含本机的 Profile 签名、校验并经 USB HDC 安装。签名材料存放在用户私有配置目录，不进入仓库。

## 当前功能状态

| 顺序 | 功能 | 当前结果 | 实现或下一步 |
| --- | --- | --- | --- |
| 1 | 性能 Tab | 已开放；CPU、内存、开机时长、电量与充电状态可读取 | `cat /proc/stat`、`cat /proc/meminfo`、`uptime`、`hidumper -s BatteryService -a -i`；设备不提供的 FPS 不展示 |
| 2 | 控制 Tab 快捷操作 | 通知中心、控制中心 HDC 手势和 Settings 首页均已真机验证；截图、录屏复用既有服务 | Settings 需使用完整 `com.huawei.hmos.settings.MainAbility`；录屏只复用系统录屏能力 |
| 3 | 只转发音频 | 签名 HAP 已安装；系统录制授权后，跨应用铃声播放时桌面收到 7432 帧、28,538,880 字节 PCM，其中 4,037,461 字节非零 | `AVScreenCapture` 原始码流只转发 `AUDIO_INNER` buffer，视频宽高为 0，mic 关闭；HDC 反向端口转发到 macOS |
| 4 | 摄像头／麦克风 | 麦克风授权后桌面收到 591 帧、2,269,440 字节 PCM，其中 1,617,120 字节非零；前后摄均显示实时预览并完成切换 | 麦克风只转发 `AUDIO_MIC` buffer；Camera Kit 会话通过 XComponent 显示，不向桌面传视频 |
| 5 | 跨应用消息 | AGC 已核对 `SUBSCRIBE_NOTIFICATION` ACL 申请规则，不符合当前桌面伴侣应用场景，未申请；HDC shell 也未读到跨应用通知正文 | AGC 明确仅允许三方手表官方应用申请，且要求展示通知同步至手表的截图／录屏；当前不开放消息 Tab |

## 性能采集细节

- HarmonyOS 设备的 `/proc/uptime` 返回 permission denied，因此命令回退至 `uptime`；解析 `up h:mm` 或 `up d days, h:mm`。
- `BatteryService` 的 `capacity` 才是百分比；`batteryLevel` 不是百分比。读不到电量时显示 `-`，不伪造 `100%`。
- 这台设备不开放 CPU 频率 sysfs；核心频率不可读时显示 `-`，采样命令不反复探测该目录。
- 不调用 Android 专用的 Rust Direct ADB Socket。采样加运行中保护，避免 HDC 慢响应引发并发轮询。
- 本机 `hidumper -s RenderService -a fpsCount` 返回刷新率计数，不等于当前应用 FPS，因此鸿蒙性能页暂不展示 FPS。

## 媒体与消息的技术边界

1. HDC 的 `hidumper -s AudioPolicyService` 是诊断数据，不能输出可播放 PCM。现有 `hoscrcpy-server` 只建立视频采集链路；`HosRemoteDevice` API 未暴露音频、摄像头或麦克风流。Android `scrcpy-server.jar` 与 ADB 音频路径不适用于 HarmonyOS。
2. 官方 `AVScreenCapture` 示例允许将视频宽高设为 0 以录制纯音频，并以 `OH_ALL_PLAYBACK` 选择设备内音频。原型使用 buffer 回调而非屏幕录制文件，真机已验证跨应用音频 PCM；长时间后台稳定性、通话打断与音频焦点仍需专项验证。
3. Camera Kit 和 AudioCapturer 必须由获授权的设备侧应用持有会话。桌面 HDC shell 不等同于相机／麦克风权限，不能从 `hidumper` 输出推断可采集。
4. `hidumper -s DistributedNotificationService -a -a` 在这台设备仅返回服务摘要，没有通知正文。该设备 API version 23；API 22 起提供 `NotificationSubscriberExtensionAbility` 与 `openSubscriptionSettings`，但 `SUBSCRIBE_NOTIFICATION` 是 `system_basic` 受限权限。2026-10-26 在本应用 AGC 的 ACL 页面查询到：仅允许三方手表官方应用申请，需提供通知同步至手表的截图／录屏。AnyDeck 桌面伴侣不符合该规则，因此不提交 ACL 申请、不开放 HarmonyOS 消息 Tab。返回授权结果的 `openSubscriptionSettingsWithResult` 从 API 26 才提供，当前设备不能调用。

## 后续专项验收

1. 做长期后台音频、通话打断、采集进程异常退出与 USB 断线回收测试；当前只确认了短时前台与跨应用播放。
2. 摄像头目前只在设备侧预览。桌面视频转发需另加编码、传输及生命周期管理，再接入控制 Tab。
3. 若未来产品转为官方手表通知同步场景，先按 AGC 规则申请 ACL 并获批，再验证配对、用户授权和通知接收；当前桌面场景不适用。

## 官方依据

- [Recording Audio Using AVScreenCapture](https://developer.huawei.com/consumer/en/doc/best-practices/bpta-audio-record-base-on-avscreencapture)
- [AVScreenCapture API](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V13/native__avscreen__capture_8h-V13)
- [Using AVScreenCapture to Record Files](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/using-avscreencapture-for-file)
- [NotificationSubscriber](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V3/notificationsubscriber-0000001054358823-V3)
- [通知订阅扩展能力开发步骤](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ion-subscriber-extension-ability-development-steps)
- [通知订阅扩展能力概述](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/notification-subscriber-extension-ability)
- [相机预配置](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/camera-preconfig-native)
- [HarmonyOS Command Line Tools](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/ide-hvigor-commandline)
