#import "ScrcpyTexture.h"

@implementation ScrcpyTexture

- (instancetype)initWithTextureRegistry:(id<FlutterTextureRegistry>)registry {
    self = [super init];
    if (self) {
        _textureRegistry = registry;
        _pixelBuffer = nil;
        _width = 0;
        _height = 0;
        _textureId = [registry registerTexture:self];
    }
    return self;
}

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
    @synchronized(self) {
        if (_pixelBuffer) {
            CFRetain(_pixelBuffer);
            return _pixelBuffer;
        }
        return nil;
    }
}

/// 接收 VideoToolbox 硬解生成的 CVPixelBufferRef 显存句柄，实现直通零拷贝渲染。
- (void)updatePixelBuffer:(CVPixelBufferRef)pixelBuffer width:(int)width height:(int)height {
    int64_t textureId = 0;
    @synchronized(self) {
        if (_textureId == 0 || !pixelBuffer) {
            return;
        }
        if (_pixelBuffer) {
            CVPixelBufferRelease(_pixelBuffer);
        }
        _pixelBuffer = CVPixelBufferRetain(pixelBuffer);
        _width = width;
        _height = height;
        textureId = _textureId;
    }

    if (textureId != 0) {
        id<FlutterTextureRegistry> textureRegistry = _textureRegistry;
        dispatch_async(dispatch_get_main_queue(), ^{
            [textureRegistry textureFrameAvailable:textureId];
        });
    }
}

- (int64_t)textureId {
    return _textureId;
}

- (void)dispose {
    @synchronized(self) {
        if (_textureId != 0) {
            [_textureRegistry unregisterTexture:_textureId];
            _textureId = 0;
        }
        if (_pixelBuffer) {
            CVPixelBufferRelease(_pixelBuffer);
            _pixelBuffer = nil;
        }
    }
}

- (void)dealloc {
    [self dispose];
}

- (CGSize)videoSize {
    @synchronized(self) {
        return CGSizeMake(_width, _height);
    }
}

@end
