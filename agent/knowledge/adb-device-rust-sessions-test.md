# 摄像头、麦克风、剪贴板：测试与回归影响

## 影响范围

直接影响使用时长弹窗的摄像头页和新增手机剪贴板页、Rust 库构建打包、各窗口 Texture 生命周期。摄像头从旧解码器切换到 Rust/VideoToolbox，需要回归前后摄、比例和停止行为。

原屏幕投屏协议和解码器不变；共享 server 资源提取方法改为可复用入口。应回归屏幕投屏与摄像头/麦克风并行运行、设备断线、关闭子窗口。原使用统计和位置页按钮保持原逻辑。

## 自动验证

```bash
flutter test --no-pub test/device_auxiliary_test.dart test/camera_preview_test.dart test/usage_report_dialog_test.dart test/embedded_camera_service_test.dart test/embedded_scrcpy_geometry_test.dart test/mirror_device_info_overlay_test.dart
cargo test --manifest-path rust/device_bridge/Cargo.toml
cargo clippy --manifest-path rust/device_bridge/Cargo.toml -- -D warnings
plutil -lint macos/Runner/Info.plist
bash script/build_device_bridge.sh
```

本地生成测试帧验证实际 VideoToolbox 解码，不打开真实摄像头：

```bash
ffmpeg -hide_banner -loglevel error -y -f lavfi -i color=red:size=64x48:rate=1 -frames:v 1 -c:v libx264 -tune zerolatency -pix_fmt yuv420p -f h264 /tmp/anydeck-test-frame.h264
ANYDECK_H264_FIXTURE=/tmp/anydeck-test-frame.h264 cargo test --manifest-path rust/device_bridge/Cargo.toml -- --include-ignored
```

本轮已通过：Flutter 33 项（中文/英文、明暗主题、API 29/30/31 门槛、纯麦克风、静音、迟到取消、剪贴板合并、停止清空、原使用统计和摄像头回归）；Rust 9 项（命令取消、输出限制、拆包、无音频标记、超长文本、Unicode、H.264 参数解析与真实生成帧解码）；Swift Texture 桥接类型检查。

全仓 `flutter analyze --no-pub` 有已有基线问题，包括 `test/apps_tab_filter_test.dart` 的缺失构造参数及未定义符号，不能声明全仓检查通过；本次相关文件另外做定向分析。

## 真机回归步骤（本轮未执行）

1. Android 10：摄像头、麦克风开始按钮禁用；剪贴板显示 ROM 兼容说明。
2. Android 11：摄像头禁用，解锁后可单独开启麦克风；验证锁屏启动失败提示及重试。
3. Android 12+：前后摄停止后切换；同时开启麦克风，停止麦克风不打断画面，停止摄像头不停止已手动开启的麦克风。
4. 监听静音时手机麦克风使用提示仍存在；停止采集后释放麦克风。系统麦克风隐私开关关闭、通话和其他录音 App 占用时验证状态提示。
5. 手机复制中文、Emoji、换行和大文本；页面显示新内容和时间。电脑剪贴板只有点击“复制到电脑”时改变。验证空剪贴板、非文本和 ROM 拒绝读取的等待说明。
6. 快速启停、启动中停止、切页、关闭弹窗、关闭原生子窗口、ADB 断线，检查传感器使用提示消失、独立进程/端口清理、无迟到纹理恢复。
7. 原屏幕投屏保持运行，同时启停这三个会话，验证不会互相停止或更改手机屏幕状态。
8. 检查中英文、深浅主题，以及较小窗口中滚动控制区仍可操作，视频区域比例正确。
9. macOS 构建后确认 Contents/Frameworks 内存在并签名 `libanydeck_device_bridge.dylib`；检查主窗口和子窗口均可注册 Rust Texture。
10. Flutter 3.47+ 检查启动日志使用 Skia 而不是 `MetalSDF`；连续重复开启/关闭投屏、横竖屏旋转和跨显示器移动，确认没有纯黑 Texture。若重新启用 Impeller，必须先完成同一组真机 A/B 回归。

连接自己的目标设备后可检查残留（不是启动命令）：

```bash
adb -s SERIAL shell ps -A
adb forward --list
```

在设备离线期间远端 jar 删除可能失败；会话不恢复为运行态。下次连接可人工检查 `/data/local/tmp/anydeck-*.jar`，不要删除其他会话正在使用的文件。
