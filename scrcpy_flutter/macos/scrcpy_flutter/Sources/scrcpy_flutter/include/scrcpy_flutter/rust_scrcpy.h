#pragma once

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*ScrcpyFrameCallback)(void* opaque, const uint8_t* rgbaBuf, int width, int height);
typedef void (*ScrcpyAudioCallback)(void* opaque, const uint8_t* pcmBuf, int len);

typedef struct RustScrcpyDecoderContext RustScrcpyDecoderContext;

RustScrcpyDecoderContext* rust_scrcpy_start(
    const char* host,
    int port,
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
