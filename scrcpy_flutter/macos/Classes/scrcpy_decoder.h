#pragma once

#ifdef __cplusplus
#include <string>
#include <thread>
#include <atomic>
#include <mutex>
#include <vector>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libavutil/imgutils.h>
}

typedef void (*ScrcpyFrameCallback)(void* opaque, const uint8_t* rgbaBuf, int width, int height);

class ScrcpyDecoder {
public:
    ScrcpyDecoder(const std::string& host, int port, ScrcpyFrameCallback callback, void* opaque);
    ~ScrcpyDecoder();

    bool Start();
    void Stop();
    bool SendControl(const uint8_t* bytes, size_t len);

private:
    void DecodeLoop();
    bool ConnectSockets();
    void Cleanup();
    bool ReadExactly(int fd, uint8_t* buf, size_t len);

    std::string host_;
    int port_;
    ScrcpyFrameCallback callback_;
    void* opaque_;

    std::thread thread_;
    std::atomic<bool> running_{false};

    int video_socket_{-1};
    int control_socket_{-1};

    // FFmpeg contexts
    const AVCodec* codec_{nullptr};
    AVCodecContext* codec_ctx_{nullptr};
    AVCodecParserContext* parser_{nullptr};
    AVFrame* frame_{nullptr};
    AVPacket* packet_{nullptr};
    SwsContext* sws_ctx_{nullptr};

    std::vector<uint8_t> rgba_buffer_;
    std::mutex socket_mutex_;
};
#endif
