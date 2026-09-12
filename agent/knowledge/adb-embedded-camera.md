# 内嵌 scrcpy 摄像头预览

## 目标与入口

使用现有原生解码器把手机摄像头画面显示在本项目 Flutter Texture 中，不启动外部 scrcpy/SDL 窗口。

入口：Android 设备 → 应用 → 使用时长 → 摄像头 → 选择前置/后置 → 开始预览。切换镜头先停止再选择；关闭弹窗或切到其它页即停止。默认无音频、不录像、不保存摄像头数据到历史库。

当前支持 macOS + Android 12（API 31）及以上。现有 Windows/Linux scrcpy 插件只有模板接口，不能宣称支持内嵌摄像头；界面在启动前给出平台限制。手机保留正常摄像头隐私提示，不实现隐藏采集或提示规避。无需安装/更新使用统计手机 App。

## 架构与复用

```text
手机 scrcpy-server 4.0 摄像头采集/H.264 编码
→ 独立 ADB forward
→ 现有 Rust TCP/帧协议解析
→ 现有 macOS 原生解码与纹理注册
→ Flutter Texture（摄像头页）
```

| 文件 | 职责 |
| --- | --- |
| `lib/core/scrcpy/scrcpy_camera_options.dart` | 固定镜头参数、随机非零 scid、独立会话名、取消令牌 |
| `lib/core/scrcpy/embedded_scrcpy_service.dart` | 复用资产推送、ADB 转发、服务启动、纹理注册与停止，增加可选 camera 参数 |
| `lib/core/scrcpy/embedded_scrcpy_providers.dart` | 从服务文件原样拆出原有 Provider，保持库内 API，避免单文件超过 500 行 |
| `lib/core/scrcpy/embedded_camera_backend.dart` | 摄像头会话适配与测试注入边界，复用 ScrcpyFlutter |
| `lib/features/apps/controller/camera_preview_controller.dart` | 手动启动、停止、首帧等待、尺寸读取、断线和销毁回收 |
| `lib/features/apps/widgets/camera_preview_view.dart` | 前后镜头选择、状态、开始/停止与按视频尺寸展示 Texture |
| `lib/features/apps/widgets/usage_report_dialog.dart` | 摄像头分页入口，与原有使用统计/地图并列 |

没有新增三方依赖、没有修改 Rust/C++/Objective-C 解码协议，没有新增 App 图标或包名获取逻辑。摄像头状态只在当前页面存活，不跨窗口广播，也不持久化成自动恢复设置。

## 会话及参数约束

- 原有屏幕投屏保持 `scid=0`、设备 ID 作为插件会话键；摄像头每次生成独立 `camera:<deviceId>:<scid>`，手机 socket 为 `scrcpy_<8位十六进制scid>`，使用独立本机环回端口。
- ADB 命令始终使用原设备 ID；插件 start/stop/getVideoSize 使用摄像头会话键，防止停止摄像头时误停同设备屏幕投屏。
- 摄像头固定 `video_source=camera`、`camera_facing=front/back`、`video_codec=h264`、`camera_fps=30`、`max_size=1280`、`video_bit_rate=4000000`、`audio=false`、`clipboard_autosync=false`。
- 使用 server 的 `key=value` 参数，不是外部 CLI 的 `--video-source` 参数。直接复用内置 `assets/scrcpy/scrcpy-server.jar` 及其匹配版本 4.0。
- 保留 `control=true`，因为现有原生客户端固定建立视频/控制连接；摄像头页不接入屏幕触摸/键盘处理，不发送屏幕控制消息。
- 摄像头模式与 newDisplay/startApp 互斥，不创建虚拟屏幕或启动相机 App。全局屏幕投屏的音频/码率设置不覆盖摄像头的固定无音频配置。

参考：[scrcpy 摄像头文档](https://github.com/Genymobile/scrcpy/blob/master/doc/camera.md)、[4.0 server 参数定义](https://github.com/Genymobile/scrcpy/blob/v4.0/server/src/main/java/com/genymobile/scrcpy/Options.java)。

## 生命周期及异常处理

- 用户点击开始才创建会话，防重复启动。启动期间也可停止；取消令牌在推送后、启动服务前、连接前和注册纹理后检查。
- 取消立即请求终止本次服务进程，2 秒未退出则强制结束本机进程；纹理及端口随后回收。
- 摄像头原生连接等待上限 15 秒，超时/取消后迟到的纹理注册结果仍触发回收。独立会话 ID 防止旧回调误停新镜头。
- 注册后每 500 毫秒查询真实解码尺寸（单次 3 秒超时、禁止重入），尺寸有效后显示 Texture；12 秒仍无画面则停止并报错。不按手机屏幕比例拉伸摄像头。
- ADB 设备离线、服务进程退出、用户停止、Provider 销毁时均释放本次会话；停止转发为幂等操作，不删除其它会话端口。
- 停止后选择镜头并再次开始，不自动持续重连。切页采用移除摄像头 Widget 的方式释放 autoDispose Provider。
- 原生视频解码异常若没有进程退出/尺寸错误，尚未有逐帧心跳来识别所有冻结画面；实际延迟、并发编码能力和镜头占用错误需真机验证。

## 测试与影响范围

直接影响摄像头页、共享 EmbeddedScrcpyService 的可选分支；需要回归原屏幕投屏、虚拟显示/单 App 投屏启动及停止。原 Provider 拆文件为机械移动，不改变其行为。

```bash
flutter test --no-pub test/embedded_camera_service_test.dart test/camera_preview_test.dart test/usage_report_dialog_test.dart
flutter analyze --no-pub
```

本轮 13 项测试通过，定向分析无问题。测试使用假 ADB 进程/原生通道和假视频尺寸，不打开真实摄像头：

- 保持屏幕默认参数；摄像头参数、无音频和独立 socket/纹理键正确。
- 停摄像头后屏幕会话仍在，删除转发使用原始 ADB 设备 ID。
- Android 11 拒绝摄像头并清理转发；取消令牌阻止迟到启动。
- 启动途中停止不恢复迟到纹理；视频进程退出清理状态。
- 中英文 × 明暗主题：进入页面不启动摄像头，点击后展示 Texture，移除页面取消会话；原使用时长/位置页回归通过。

真机手工回归：

1. macOS 进入摄像头页，手机无摄像头占用；点击开始后本页面出现画面且手机有系统提示。
2. 停止 → 切前置 → 开始；检查画面比例、旋转和镜头是否正确。
3. 启动中快速关页、运行中切页、关闭弹窗、切换设备、断开 ADB，确认手机停止使用摄像头。
4. 摄像头被其它 App 占用时应报错；停止后可重试。
5. 原屏幕投屏/单 App 投屏仍可启停；测试设备可能因编码资源不足不支持同时采集，不能仅凭会话隔离测试承诺并发成功。

未启动桌面项目或真实摄像头，实际设备视频效果尚待用户在页面点击开始验证。
