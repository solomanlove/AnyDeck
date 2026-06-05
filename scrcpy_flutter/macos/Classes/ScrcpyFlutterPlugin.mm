#import "ScrcpyFlutterPlugin.h"
#import "ScrcpyTexture.h"
#include "scrcpy_decoder.h"
#include <map>
#include <memory>
#include <string>

struct ScrcpySessionData {
    std::unique_ptr<ScrcpyDecoder> decoder;
    ScrcpyTexture* texture;
};

static void scrcpy_frame_callback(void* opaque, const uint8_t* rgbaBuf, int width, int height) {
    ScrcpyTexture* texture = (__bridge ScrcpyTexture*)opaque;
    [texture updateFrame:rgbaBuf width:width height:height];
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
        pair.second.decoder->Stop();
        [pair.second.texture dispose];
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
            it->second.decoder->Stop();
            [it->second.texture dispose];
            _sessions.erase(it);
        }
        
        ScrcpyTexture* texture = [[ScrcpyTexture alloc] initWithTextureRegistry:_textureRegistry];
        void* opaque = (__bridge void*)texture;
        
        auto decoder = std::make_unique<ScrcpyDecoder>(
            [host UTF8String],
            [portNum intValue],
            audioEnabled,
            scrcpy_frame_callback,
            opaque
        );
        
        if (!decoder->Start()) {
            [texture dispose];
            result([FlutterError errorWithCode:@"START_FAILED"
                                     message:@"Failed to start scrcpy decoder thread"
                                     details:nil]);
            return;
        }
        
        ScrcpySessionData session;
        session.decoder = std::move(decoder);
        session.texture = texture;
        _sessions[devId] = std::move(session);
        
        result(@([texture textureId]));
        
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
            it->second.decoder->Stop();
            [it->second.texture dispose];
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
        if (it == _sessions.end() || !it->second.texture) {
            result(nil);
            return;
        }
        
        int width = [it->second.texture width];
        int height = [it->second.texture height];
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
        
        bool success = it->second.decoder->SendControl(bytes, len);
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
