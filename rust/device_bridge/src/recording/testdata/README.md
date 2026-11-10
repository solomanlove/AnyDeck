# 固定音视频测试流

自行生成的测试图案与正弦音，不含用户或设备数据。测试不要求运行时安装 FFmpeg。

```bash
ffmpeg -f lavfi -i 'testsrc2=size=320x240:rate=10' -t 1 -c:v libx264 -profile:v baseline -bf 0 -g 1 -f h264 video.h264
ffmpeg -f lavfi -i 'sine=frequency=440:sample_rate=48000' -t 1 -ac 2 -c:a aac -b:a 128k -f adts audio.aac
```

Rust 测试移除 ADTS 头，将 AAC AudioSpecificConfig 和 H.264 SPS/PPS 按 scrcpy 4.0 协议输入。除了 MP4 读回测试，也通过本地 socket 和模拟 ADB 验证 C ABI 录制与资源清理。文件只在 `cfg(test)` 下编译，不进入产品动态库。
