#ifndef RUST_SCRCPY_H
#define RUST_SCRCPY_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RustScrcpyDecoderContext RustScrcpyDecoderContext;

/// 视频帧硬件解码回调：pixel_buffer 为 CVPixelBufferRef 指针。
typedef void (*ScrcpyFrameCallback)(void* opaque, void* pixel_buffer, int32_t width, int32_t height);
typedef void (*ScrcpyAudioCallback)(void* opaque, const uint8_t* pcm_buf, int32_t len);

RustScrcpyDecoderContext* rust_scrcpy_start(
    const char* host,
    int32_t port,
    bool audio_enabled,
    ScrcpyFrameCallback frame_cb,
    ScrcpyAudioCallback audio_cb,
    void* opaque
);

void rust_scrcpy_stop(RustScrcpyDecoderContext* ctx);

bool rust_scrcpy_send_control(RustScrcpyDecoderContext* ctx, const uint8_t* bytes, size_t len);

#ifdef __cplusplus
}
#endif

#endif // RUST_SCRCPY_H
