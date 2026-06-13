#pragma once

#ifdef __cplusplus
#include <string>
#include <thread>
#include <atomic>
#include <mutex>
#include <condition_variable>
#include <vector>
#include <AudioToolbox/AudioToolbox.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#pragma clang diagnostic ignored "-Wdocumentation-html"
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libavutil/imgutils.h>
#include <libswresample/swresample.h>
}
#pragma clang diagnostic pop

typedef void (*ScrcpyFrameCallback)(void* opaque, const uint8_t* rgbaBuf, int width, int height);

class ScrcpyDecoder {
public:
    ScrcpyDecoder(const std::string& host, int port, bool audio_enabled, ScrcpyFrameCallback callback, void* opaque);
    ~ScrcpyDecoder();

    bool Start();
    void Stop();
    bool SendControl(const uint8_t* bytes, size_t len);
    void ReleaseAudioBuffer(AudioQueueBufferRef buffer);

private:
    void DecodeLoop();
    void AudioLoop();
    bool ConnectSockets();
    void Cleanup();
    void CleanupAudio();
    bool ReadExactly(int fd, uint8_t* buf, size_t len);

    std::string host_;
    int port_;
    bool audio_enabled_;
    ScrcpyFrameCallback callback_;
    void* opaque_;

    std::thread thread_;
    std::thread audio_thread_;
    std::atomic<bool> running_{false};

    int video_socket_{-1};
    int audio_socket_{-1};
    int control_socket_{-1};

    // FFmpeg contexts for Video
    const AVCodec* codec_{nullptr};
    AVCodecContext* codec_ctx_{nullptr};
    AVCodecParserContext* parser_{nullptr};
    AVFrame* frame_{nullptr};
    AVPacket* packet_{nullptr};
    SwsContext* sws_ctx_{nullptr};

    std::vector<uint8_t> rgba_buffer_;
    std::mutex socket_mutex_;

    // FFmpeg & AudioQueue variables for Audio
    const AVCodec* audio_codec_{nullptr};
    AVCodecContext* audio_codec_ctx_{nullptr};
    AVFrame* audio_frame_{nullptr};
    AVPacket* audio_packet_{nullptr};
    SwrContext* swr_ctx_{nullptr};

    AudioQueueRef audio_queue_{nullptr};
    std::vector<AudioQueueBufferRef> free_audio_buffers_;
    std::mutex audio_buf_mutex_;
    std::condition_variable audio_buf_cond_;
};
#endif
