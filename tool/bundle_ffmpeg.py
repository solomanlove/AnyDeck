#!/usr/bin/env python3
"""
[DEPRECATED / 废弃]
AnyDeck 已彻底剥离外部 FFmpeg 动态库，视频解码全面迁移至纯 Rust + macOS VideoToolbox 硬件解码，
音频输出全面迁移至纯 Rust + macOS AudioQueue 直通播放。
本项目不再需要也不再打包任何外部 FFmpeg .dylib 动态库文件。
"""
import sys

def main():
    print("[DEPRECATED] FFmpeg bundling is no longer required. AnyDeck now uses pure Rust + VideoToolbox & AudioQueue.")
    sys.exit(0)

if __name__ == "__main__":
    main()
