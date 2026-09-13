#import "ScrcpyFlutterPlugin.h"
#import "ScrcpyTexture.h"
#import "rust_scrcpy.h"
#include <map>
#include <memory>
#include <string>
#include <vector>
#include <iostream>

struct ScrcpySessionContext {
    ScrcpyTexture* texture;
};

static void scrcpy_frame_callback(void* opaque, void* pixel_buffer, int32_t width, int32_t height) {
    if (!opaque || !pixel_buffer) return;
    ScrcpySessionContext* context = static_cast<ScrcpySessionContext*>(opaque);
    if (context && context->texture) {
        [context->texture updatePixelBuffer:static_cast<CVPixelBufferRef>(pixel_buffer)
                                      width:width
                                     height:height];
    }
}

static void scrcpy_audio_callback(void* opaque, const uint8_t* pcm_buf, int32_t len) {
    // 音频流已在纯 Rust 内部由 AudioQueue 直通低延迟播放
    (void)opaque;
    (void)pcm_buf;
    (void)len;
}

struct ScrcpySessionData {
    RustScrcpyDecoderContext* decoder;
    std::unique_ptr<ScrcpySessionContext> context;
};

@implementation ScrcpyFlutterPlugin {
    NSObject<FlutterTextureRegistry>* _textureRegistry;
    NSObject<FlutterPluginRegistrar>* _registrar;
    std::map<std::string, ScrcpySessionData> _sessions;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
        methodChannelWithName:@"scrcpy_flutter"
              binaryMessenger:[registrar messenger]];
    ScrcpyFlutterPlugin* instance = [[ScrcpyFlutterPlugin alloc] initWithRegistrar:registrar];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
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
    struct StopRequest {
        RustScrcpyDecoderContext* decoder;
        ScrcpySessionContext* rawContext;
    };
    std::vector<StopRequest> requests;
    
    for (auto& pair : _sessions) {
        [pair.second.context->texture dispose];
        requests.push_back({pair.second.decoder, pair.second.context.release()});
    }
    _sessions.clear();
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (auto& req : requests) {
            rust_scrcpy_stop(req.decoder);
            delete req.rawContext;
        }
    });
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
        
        // 清理同设备的先前残留会话
        auto it = _sessions.find(devId);
        if (it != _sessions.end()) {
            rust_scrcpy_stop(it->second.decoder);
            [it->second.context->texture dispose];
            _sessions.erase(it);
        }
        
        auto context = std::make_unique<ScrcpySessionContext>();
        context->texture = [[ScrcpyTexture alloc] initWithTextureRegistry:_textureRegistry];
        
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
                                     message:@"Failed to start scrcpy decoder thread (Rust VideoToolbox)"
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
            [it->second.context->texture dispose];
            RustScrcpyDecoderContext* decoder = it->second.decoder;
            ScrcpySessionContext* rawContext = it->second.context.release();
            _sessions.erase(it);
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                rust_scrcpy_stop(decoder);
                delete rawContext;
            });
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
        
        CGSize videoSize = [it->second.context->texture videoSize];
        int width = static_cast<int>(videoSize.width);
        int height = static_cast<int>(videoSize.height);
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
