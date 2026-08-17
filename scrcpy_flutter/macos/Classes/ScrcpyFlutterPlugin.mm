#import "ScrcpyFlutterPlugin.h"
#import "ScrcpyTexture.h"
#import "rust_scrcpy.h"
#include <map>
#include <memory>
#include <string>
#include <vector>
#include <mutex>
#include <iostream>
#include <AudioToolbox/AudioToolbox.h>

#ifdef __cplusplus
extern "C" {
#endif
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/opt.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#ifdef __cplusplus
}
#endif

class ScrcpyAudioPlayer {
public:
    ScrcpyAudioPlayer() {
        AudioStreamBasicDescription asbd;
        std::memset(&asbd, 0, sizeof(asbd));
        asbd.mSampleRate = 48000.0;
        asbd.mFormatID = kAudioFormatLinearPCM;
        asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        asbd.mBytesPerPacket = 4;
        asbd.mFramesPerPacket = 1;
        asbd.mBytesPerFrame = 4;
        asbd.mChannelsPerFrame = 2;
        asbd.mBitsPerChannel = 16;

        OSStatus status = AudioQueueNewOutput(&asbd, AudioQueueCallback, this, nullptr, nullptr, 0, &audio_queue_);
        if (status == noErr) {
            for (int i = 0; i < 3; ++i) {
                AudioQueueBufferRef buf = nullptr;
                AudioQueueAllocateBuffer(audio_queue_, 8192, &buf);
                if (buf) {
                    free_buffers_.push_back(buf);
                }
            }
            AudioQueueStart(audio_queue_, nullptr);
            std::cout << "[ScrcpyAudioPlayer] macOS AudioQueue started" << std::endl;
        } else {
            std::cerr << "[ScrcpyAudioPlayer] AudioQueueNewOutput failed: " << status << std::endl;
        }
    }

    ~ScrcpyAudioPlayer() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (audio_queue_) {
            AudioQueueStop(audio_queue_, true);
            for (auto buf : free_buffers_) {
                AudioQueueFreeBuffer(audio_queue_, buf);
            }
            free_buffers_.clear();
            AudioQueueDispose(audio_queue_, true);
            audio_queue_ = nullptr;
        }
        std::cout << "[ScrcpyAudioPlayer] AudioQueue destroyed" << std::endl;
    }

    void PlayPCM(const uint8_t* data, int len) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!audio_queue_ || free_buffers_.empty()) return;

        AudioQueueBufferRef buf = free_buffers_.back();
        free_buffers_.pop_back();

        size_t copy_size = std::min((size_t)len, (size_t)buf->mAudioDataBytesCapacity);
        std::memcpy(buf->mAudioData, data, copy_size);
        buf->mAudioDataByteSize = (UInt32)copy_size;

        AudioQueueEnqueueBuffer(audio_queue_, buf, 0, nullptr);
    }

    void ReleaseBuffer(AudioQueueBufferRef buffer) {
        std::lock_guard<std::mutex> lock(mutex_);
        free_buffers_.push_back(buffer);
    }

private:
    static void AudioQueueCallback(void* custom_data, AudioQueueRef queue, AudioQueueBufferRef buffer) {
        ScrcpyAudioPlayer* player = static_cast<ScrcpyAudioPlayer*>(custom_data);
        player->ReleaseBuffer(buffer);
    }

    AudioQueueRef audio_queue_{nullptr};
    std::vector<AudioQueueBufferRef> free_buffers_;
    std::mutex mutex_;
};

struct ScrcpySessionContext {
    ScrcpyTexture* texture;
    std::shared_ptr<ScrcpyAudioPlayer> audioPlayer;
};

extern "C" {

struct rust_decoder_context {
    AVCodecContext *codec_ctx;
    const AVCodec *codec;
    AVCodecParserContext *parser;
    AVPacket *packet;
    AVFrame *frame;
    struct SwsContext *sws_ctx;
    ScrcpySessionContext *session_ctx;
    std::vector<uint8_t> rgba_buf;
};

struct rust_audio_decoder_context {
    AVCodecContext *codec_ctx;
    const AVCodec *codec;
    AVPacket *packet;
    AVFrame *frame;
    struct SwrContext *swr_ctx;
    ScrcpySessionContext *session_ctx;
    std::vector<uint8_t> pcm_buf;
    bool raw_pcm;
};

void* rust_helper_create_decoder(void* session_ctx_ptr, uint32_t codec_id) {
    ScrcpySessionContext* session_ctx = static_cast<ScrcpySessionContext*>(session_ctx_ptr);
    if (!session_ctx) return nullptr;

    rust_decoder_context* ctx = new rust_decoder_context();
    ctx->session_ctx = session_ctx;
    ctx->sws_ctx = nullptr;

    AVCodecID ffmpeg_codec_id = (codec_id == 0x68323635) ? AV_CODEC_ID_HEVC : AV_CODEC_ID_H264;
    ctx->codec = avcodec_find_decoder(ffmpeg_codec_id);
    if (!ctx->codec) {
        delete ctx;
        return nullptr;
    }

    ctx->codec_ctx = avcodec_alloc_context3(ctx->codec);
    if (!ctx->codec_ctx) {
        delete ctx;
        return nullptr;
    }

    if (avcodec_open2(ctx->codec_ctx, ctx->codec, nullptr) < 0) {
        avcodec_free_context(&ctx->codec_ctx);
        delete ctx;
        return nullptr;
    }

    ctx->parser = av_parser_init(ffmpeg_codec_id);
    if (!ctx->parser) {
        avcodec_free_context(&ctx->codec_ctx);
        delete ctx;
        return nullptr;
    }

    ctx->packet = av_packet_alloc();
    ctx->frame = av_frame_alloc();
    return ctx;
}

void rust_helper_destroy_decoder(void* decoder_ptr) {
    rust_decoder_context* ctx = static_cast<rust_decoder_context*>(decoder_ptr);
    if (!ctx) return;

    if (ctx->codec_ctx) avcodec_free_context(&ctx->codec_ctx);
    if (ctx->parser) av_parser_close(ctx->parser);
    if (ctx->packet) av_packet_free(&ctx->packet);
    if (ctx->frame) av_frame_free(&ctx->frame);
    if (ctx->sws_ctx) sws_freeContext(ctx->sws_ctx);
    delete ctx;
}

void rust_helper_decode_video_packet(
    void* decoder_ptr,
    const uint8_t* data,
    int size,
    int64_t pts,
    int stream_width,
    int stream_height
) {
    rust_decoder_context* ctx = static_cast<rust_decoder_context*>(decoder_ptr);
    if (!ctx || !ctx->codec_ctx || !ctx->packet || !ctx->frame || !ctx->parser) return;

    const uint8_t* parse_in = data;
    int parse_in_len = size;

    while (parse_in_len > 0) {
        uint8_t* parsed_data = nullptr;
        int parsed_size = 0;

        int parsed = av_parser_parse2(
            ctx->parser,
            ctx->codec_ctx,
            &parsed_data,
            &parsed_size,
            parse_in,
            parse_in_len,
            pts,
            AV_NOPTS_VALUE,
            0
        );

        parse_in += parsed;
        parse_in_len -= parsed;

        if (parsed_size > 0) {
            ctx->packet->data = parsed_data;
            ctx->packet->size = parsed_size;
            ctx->packet->pts = pts;

            int send_res = avcodec_send_packet(ctx->codec_ctx, ctx->packet);
            if (send_res < 0) continue;

            while (avcodec_receive_frame(ctx->codec_ctx, ctx->frame) >= 0) {
                int w = stream_width;
                int h = stream_height;
                if (w <= 0 || h <= 0 || w > 4096 || h > 4096) continue;

                size_t rgba_size = w * h * 4;
                if (ctx->rgba_buf.size() < rgba_size) {
                    ctx->rgba_buf.resize(rgba_size, 0);
                }

                ctx->sws_ctx = sws_getCachedContext(
                    ctx->sws_ctx,
                    w,
                    h,
                    (AVPixelFormat)ctx->frame->format,
                    w,
                    h,
                    AV_PIX_FMT_BGRA,
                    SWS_BILINEAR,
                    nullptr,
                    nullptr,
                    nullptr
                );

                if (ctx->sws_ctx) {
                    uint8_t* dst[8] = { ctx->rgba_buf.data(), nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr };
                    int dst_stride[8] = { w * 4, 0, 0, 0, 0, 0, 0, 0 };

                    sws_scale(
                        ctx->sws_ctx,
                        ctx->frame->data,
                        ctx->frame->linesize,
                        0,
                        h,
                        dst,
                        dst_stride
                    );

                    if (ctx->session_ctx && ctx->session_ctx->texture) {
                        [ctx->session_ctx->texture updateFrame:ctx->rgba_buf.data() width:w height:h];
                    }
                }
            }
        }
    }
}

void* rust_helper_create_audio_decoder(void* session_ctx_ptr, uint32_t codec_id) {
    ScrcpySessionContext* session_ctx = static_cast<ScrcpySessionContext*>(session_ctx_ptr);
    if (!session_ctx) return nullptr;

    rust_audio_decoder_context* ctx = new rust_audio_decoder_context();
    ctx->session_ctx = session_ctx;
    ctx->swr_ctx = nullptr;

    AVCodecID ffmpeg_codec_id = AV_CODEC_ID_NONE;
    if (codec_id == 0x6f707573) {
        ffmpeg_codec_id = AV_CODEC_ID_OPUS;
    } else if (codec_id == 0x61616300 || codec_id == 0x61616320) {
        ffmpeg_codec_id = AV_CODEC_ID_AAC;
    }

    ctx->raw_pcm = (ffmpeg_codec_id == AV_CODEC_ID_NONE);
    ctx->codec_ctx = nullptr;
    ctx->codec = nullptr;
    ctx->packet = nullptr;
    ctx->frame = nullptr;

    if (!ctx->raw_pcm) {
        ctx->codec = avcodec_find_decoder(ffmpeg_codec_id);
        if (!ctx->codec) {
            delete ctx;
            return nullptr;
        }

        ctx->codec_ctx = avcodec_alloc_context3(ctx->codec);
        if (!ctx->codec_ctx) {
            delete ctx;
            return nullptr;
        }

        ctx->codec_ctx->sample_rate = 48000;
        ctx->codec_ctx->request_sample_fmt = AV_SAMPLE_FMT_FLTP;

        if (avcodec_open2(ctx->codec_ctx, ctx->codec, nullptr) < 0) {
            avcodec_free_context(&ctx->codec_ctx);
            delete ctx;
            return nullptr;
        }

        ctx->packet = av_packet_alloc();
        ctx->frame = av_frame_alloc();
    }

    return ctx;
}

void rust_helper_destroy_audio_decoder(void* decoder_ptr) {
    rust_audio_decoder_context* ctx = static_cast<rust_audio_decoder_context*>(decoder_ptr);
    if (!ctx) return;

    if (ctx->codec_ctx) avcodec_free_context(&ctx->codec_ctx);
    if (ctx->packet) av_packet_free(&ctx->packet);
    if (ctx->frame) av_frame_free(&ctx->frame);
    if (ctx->swr_ctx) swr_free(&ctx->swr_ctx);
    delete ctx;
}

void rust_helper_decode_audio_packet(
    void* decoder_ptr,
    const uint8_t* data,
    int size,
    int64_t pts,
    bool is_config
) {
    rust_audio_decoder_context* ctx = static_cast<rust_audio_decoder_context*>(decoder_ptr);
    if (!ctx) return;

    if (is_config) {
        if (ctx->codec_ctx && ctx->codec) {
            ctx->codec_ctx->sample_rate = 48000;
            ctx->codec_ctx->request_sample_fmt = AV_SAMPLE_FMT_FLTP;
            if (ctx->codec_ctx->extradata) {
                av_free(ctx->codec_ctx->extradata);
                ctx->codec_ctx->extradata = nullptr;
            }
            ctx->codec_ctx->extradata = (uint8_t *)av_mallocz(size + AV_INPUT_BUFFER_PADDING_SIZE);
            if (ctx->codec_ctx->extradata) {
                std::memcpy(ctx->codec_ctx->extradata, data, size);
                ctx->codec_ctx->extradata_size = size;
            }
        }
        return;
    }

    if (ctx->raw_pcm) {
        if (ctx->session_ctx && ctx->session_ctx->audioPlayer) {
            ctx->session_ctx->audioPlayer->PlayPCM(data, size);
        }
        return;
    }

    if (!ctx->codec_ctx || !ctx->packet || !ctx->frame) return;

    ctx->packet->data = const_cast<uint8_t*>(data);
    ctx->packet->size = size;
    ctx->packet->pts = pts;

    int send_res = avcodec_send_packet(ctx->codec_ctx, ctx->packet);
    if (send_res < 0) return;

    while (avcodec_receive_frame(ctx->codec_ctx, ctx->frame) >= 0) {
        if (!ctx->swr_ctx) {
            AVChannelLayout out_ch_layout;
            av_channel_layout_default(&out_ch_layout, 2);

            AVChannelLayout in_ch_layout;
            if (ctx->frame->ch_layout.nb_channels > 0) {
                av_channel_layout_copy(&in_ch_layout, &ctx->frame->ch_layout);
            } else {
                av_channel_layout_default(&in_ch_layout, 2);
            }

            int ret = swr_alloc_set_opts2(
                &ctx->swr_ctx,
                &out_ch_layout,
                AV_SAMPLE_FMT_S16,
                48000,
                &in_ch_layout,
                (AVSampleFormat)ctx->frame->format,
                ctx->frame->sample_rate,
                0,
                nullptr
            );

            av_channel_layout_uninit(&out_ch_layout);
            av_channel_layout_uninit(&in_ch_layout);

            if (ret < 0 || swr_init(ctx->swr_ctx) < 0) {
                ctx->swr_ctx = nullptr;
                break;
            }
        }

        if (ctx->swr_ctx) {
            int nb_samples = ctx->frame->nb_samples;
            int out_samples = swr_get_out_samples(ctx->swr_ctx, nb_samples);
            size_t pcm_buf_size = out_samples * 4;
            if (ctx->pcm_buf.size() < pcm_buf_size) {
                ctx->pcm_buf.resize(pcm_buf_size, 0);
            }

            uint8_t* out_data[8] = { ctx->pcm_buf.data(), nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr };
            int converted = swr_convert(ctx->swr_ctx, out_data, out_samples, (const uint8_t **)ctx->frame->data, ctx->frame->nb_samples);

            if (converted > 0) {
                int pcm_len = converted * 4;
                if (ctx->session_ctx && ctx->session_ctx->audioPlayer) {
                    ctx->session_ctx->audioPlayer->PlayPCM(ctx->pcm_buf.data(), pcm_len);
                }
            }
        }
    }
}

}

struct ScrcpySessionData {
    RustScrcpyDecoderContext* decoder;
    std::unique_ptr<ScrcpySessionContext> context;
};

static void scrcpy_frame_callback(void* opaque, const uint8_t* rgbaBuf, int width, int height) {
    ScrcpySessionContext* ctx = static_cast<ScrcpySessionContext*>(opaque);
    if (ctx && ctx->texture) {
        [ctx->texture updateFrame:rgbaBuf width:width height:height];
    }
}

static void scrcpy_audio_callback(void* opaque, const uint8_t* pcmBuf, int len) {
    ScrcpySessionContext* ctx = static_cast<ScrcpySessionContext*>(opaque);
    if (ctx && ctx->audioPlayer) {
        ctx->audioPlayer->PlayPCM(pcmBuf, len);
    }
}

@implementation ScrcpyFlutterPlugin {
    id<FlutterTextureRegistry> _textureRegistry;
    std::map<std::string, ScrcpySessionData> _sessions;
    __weak id<FlutterPluginRegistrar> _registrar;
}

+ (void)registerWithRegistrar:(id<FlutterPluginRegistrar>)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
        methodChannelWithName:@"scrcpy_flutter"
              binaryMessenger:[registrar messenger]];
    ScrcpyFlutterPlugin* instance = [[ScrcpyFlutterPlugin alloc] initWithRegistrar:registrar];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithRegistrar:(id<FlutterPluginRegistrar>)registrar {
    self = [super init];
    if (self) {
        _textureRegistry = [registrar textures];
        _registrar = registrar;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowWillClose:)
                                                     name:NSWindowWillCloseNotification
                                                   object:nil];
    }
    return self;
}

- (void)windowWillClose:(NSNotification *)notification {
    NSWindow* closingWindow = notification.object;
    if (closingWindow && [_registrar view] && [_registrar view].window == closingWindow) {
        [self stopAllSessions];
    }
}

- (void)stopAllSessions {
    for (auto& pair : _sessions) {
        rust_scrcpy_stop(pair.second.decoder);
        [pair.second.context->texture dispose];
    }
    _sessions.clear();
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"startMirroring" isEqualToString:call.method]) {
        NSString* deviceId = call.arguments[@"deviceId"];
        NSString* host = call.arguments[@"host"] ?: @"127.0.0.1";
        NSNumber* portNum = call.arguments[@"port"];
        NSNumber* audioNum = call.arguments[@"audio"];
        bool audioEnabled = audioNum ? [audioNum boolValue] : false;
        
        if (!deviceId || !portNum) {
            result([FlutterError errorWithCode:@"INVALID_ARGUMENT"
                                     message:@"deviceId and port are required"
                                     details:nil]);
            return;
        }
        
        std::string devId = [deviceId UTF8String];
        
        // Clean up previous session for same device if exists
        auto it = _sessions.find(devId);
        if (it != _sessions.end()) {
            rust_scrcpy_stop(it->second.decoder);
            [it->second.context->texture dispose];
            _sessions.erase(it);
        }
        
        auto context = std::make_unique<ScrcpySessionContext>();
        context->texture = [[ScrcpyTexture alloc] initWithTextureRegistry:_textureRegistry];
        if (audioEnabled) {
            context->audioPlayer = std::make_shared<ScrcpyAudioPlayer>();
        }
        
        RustScrcpyDecoderContext* decoder = rust_scrcpy_start(
            [host UTF8String],
            [portNum intValue],
            audioEnabled,
            scrcpy_frame_callback,
            scrcpy_audio_callback,
            context.get()
        );
        
        if (!decoder) {
            [context->texture dispose];
            result([FlutterError errorWithCode:@"START_FAILED"
                                     message:@"Failed to start scrcpy decoder thread (Rust)"
                                     details:nil]);
            return;
        }
        
        ScrcpySessionData session;
        session.decoder = decoder;
        session.context = std::move(context);
        _sessions[devId] = std::move(session);
        
        result(@([_sessions[devId].context->texture textureId]));
        
    } else if ([@"stopMirroring" isEqualToString:call.method]) {
        NSString* deviceId = call.arguments[@"deviceId"];
        if (!deviceId) {
            result([FlutterError errorWithCode:@"INVALID_ARGUMENT"
                                     message:@"deviceId is required"
                                     details:nil]);
            return;
        }
        
        std::string devId = [deviceId UTF8String];
        auto it = _sessions.find(devId);
        if (it != _sessions.end()) {
            rust_scrcpy_stop(it->second.decoder);
            [it->second.context->texture dispose];
            _sessions.erase(it);
        }
        result(nil);
        
    } else if ([@"getVideoSize" isEqualToString:call.method]) {
        NSString* deviceId = call.arguments[@"deviceId"];
        if (!deviceId) {
            result([FlutterError errorWithCode:@"INVALID_ARGUMENT"
                                     message:@"deviceId is required"
                                     details:nil]);
            return;
        }
        
        std::string devId = [deviceId UTF8String];
        auto it = _sessions.find(devId);
        if (it == _sessions.end() || !it->second.context || !it->second.context->texture) {
            result(nil);
            return;
        }
        
        int width = [it->second.context->texture width];
        int height = [it->second.context->texture height];
        result(@{@"width": @(width), @"height": @(height)});
        
    } else if ([@"sendControl" isEqualToString:call.method]) {
        NSString* deviceId = call.arguments[@"deviceId"];
        FlutterStandardTypedData* messageData = call.arguments[@"controlMessage"];
        
        if (!deviceId || !messageData) {
            result([FlutterError errorWithCode:@"INVALID_ARGUMENT"
                                     message:@"deviceId and controlMessage are required"
                                     details:nil]);
            return;
        }
        
        std::string devId = [deviceId UTF8String];
        auto it = _sessions.find(devId);
        if (it == _sessions.end()) {
            result(@NO);
            return;
        }
        
        NSData* data = [messageData data];
        const uint8_t* bytes = (const uint8_t*)[data bytes];
        size_t len = [data length];
        
        bool success = rust_scrcpy_send_control(it->second.decoder, bytes, len);
        result(@(success));
        
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopAllSessions];
}

@end
