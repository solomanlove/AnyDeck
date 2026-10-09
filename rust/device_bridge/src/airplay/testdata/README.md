# 解码回归样本

`blue_64x48.h264` 是本地生成的单帧蓝色色块，不含真机或用户画面：

```bash
ffmpeg -f lavfi -i color=c=blue:s=64x48:r=1 -frames:v 1 -c:v libx264 -pix_fmt yuv420p -f h264 blue_64x48.h264
```

用于验证 VideoToolbox 输出 IOSurface、断流清帧及再次解码；不替代真实 AirPlay 加密媒体验收。
