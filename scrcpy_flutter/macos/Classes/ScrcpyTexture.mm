#import "ScrcpyTexture.h"
#import <cstring>

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

- (void)updateFrame:(const uint8_t *)rgbaBuffer width:(int)width height:(int)height {
    @synchronized(self) {
        if (_textureId == 0) {
            return;
        }
        if (!_pixelBuffer || _width != width || _height != height) {
            if (_pixelBuffer) {
                CVPixelBufferRelease(_pixelBuffer);
                _pixelBuffer = nil;
            }
            _width = width;
            _height = height;
            
            NSDictionary *options = @{
                (id)kCVPixelBufferCGImageCompatibilityKey : @YES,
                (id)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
                (id)kCVPixelBufferMetalCompatibilityKey : @YES,
                (id)kCVPixelBufferIOSurfacePropertiesKey : @{}
            };
            
            CVReturn status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                (__bridge CFDictionaryRef)options,
                &_pixelBuffer
            );
            if (status != kCVReturnSuccess) {
                return;
            }
        }
        
        CVPixelBufferLockBaseAddress(_pixelBuffer, 0);
        void *baseAddress = CVPixelBufferGetBaseAddress(_pixelBuffer);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(_pixelBuffer);
        
        const uint8_t *src = rgbaBuffer;
        uint8_t *dst = (uint8_t *)baseAddress;
        for (int y = 0; y < height; ++y) {
            std::memcpy(dst + y * bytesPerRow, src + y * width * 4, width * 4);
        }
        
        CVPixelBufferUnlockBaseAddress(_pixelBuffer, 0);
        
        [_textureRegistry textureFrameAvailable:_textureId];
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

- (int)width {
    return _width;
}

- (int)height {
    return _height;
}

@end
