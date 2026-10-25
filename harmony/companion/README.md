# AnyDeck HarmonyOS Companion 原型

独立 HAP，用于验证 HarmonyOS 设备内音频与麦克风 PCM 转发，以及前后摄 Camera Kit 前台预览。音频采集使用 `AVScreenCapture` 原始码流，视频宽高为 0；设备内音频模式关闭麦克风，并且只接收 `AUDIO_INNER` buffer。麦克风模式单独申请权限并且只接收 `AUDIO_MIC` buffer。系统录制授权由 HarmonyOS 弹窗决定。摄像头预览仅显示在设备上，不向桌面传视频；组件销毁时释放会话。

## 构建

使用官方 HarmonyOS Command Line Tools 6.1.1，在本目录执行：

```sh
hvigorw --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon
```

`build-profile.json5` 未包含签名材料。真机安装前需为 `com.anydeck.harmonycompanion` 申请 HarmonyOS 调试证书和包含目标设备 UDID 的 Profile；密钥、证书、Profile 均不能提交到仓库。本次已用专用调试证书签名并在 `ADA-AL00U` 安装。未签名 HAP 会被零售设备以 `9568320 no signature file` 拒绝。

桌面端先运行接收器，再打开 Companion 点击“只转发设备内音频”或“转发麦克风”：

```sh
HDC=/path/to/hdc dart run tool/harmony_audio_receiver.dart <HDC-USB设备ID>
```

接收器使用本机 `ffplay` 播放；退出时清理 HDC 反向端口。

## 转发协议

设备应用连接 `127.0.0.1:26733`，由 HDC `rport` 反向转发到 macOS 本地监听器。首 16 字节为 `ADBAUD1\0`、采样率小端 `48000`、通道数 `2`、样本字节数 `2`、源类型（0 设备内音频／1 麦克风）、保留字节。之后每帧为 4 字节小端长度和 PCM 数据。采集回调仅复制 buffer 到有界队列，独立线程发送；队列满时丢弃新帧，避免阻塞音频线程。

真机已验证：跨应用系统铃声播放时，设备内音频有非零 PCM；麦克风授权后也收到非零 PCM，前后摄可实时预览和切换。摄像头暂不向桌面传输，长期后台与断线回收仍需专项测试。源码从 [华为官方 Apache-2.0 示例](https://gitcode.com/HarmonyOS_Samples/avscreen-capture-record-system-audio-arkts) 的工程配置起步，保留了原 `LICENSE`。
