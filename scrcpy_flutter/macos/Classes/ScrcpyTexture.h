#import <FlutterMacOS/FlutterMacOS.h>
#import <CoreVideo/CoreVideo.h>

@interface ScrcpyTexture : NSObject<FlutterTexture> {
    id<FlutterTextureRegistry> _textureRegistry;
    int64_t _textureId;
    CVPixelBufferRef _pixelBuffer;
    int _width;
    int _height;
}

- (instancetype)initWithTextureRegistry:(id<FlutterTextureRegistry>)registry;
- (void)updateFrame:(const uint8_t *)rgbaBuffer width:(int)width height:(int)height;
- (int64_t)textureId;
- (void)dispose;
- (int)width;
- (int)height;

@end
