//! Apple SDK 原生 C ABI 声明，控制、内存所有权与解码流程均在 Rust。
use std::ffi::c_void;
pub type Ref = *mut c_void;
#[repr(C)]
#[derive(Clone, Copy)]
pub struct Time {
    pub value: i64,
    pub scale: i32,
    pub flags: u32,
    pub epoch: i64,
}
#[repr(C)]
pub struct Timing {
    pub duration: Time,
    pub presentation: Time,
    pub decode: Time,
}
#[repr(C)]
pub struct Callback {
    pub function: extern "C" fn(Ref, Ref, i32, u32, Ref, Time, Time),
    pub user: Ref,
}
#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    pub static kCFTypeDictionaryKeyCallBacks: [usize; 6];
    pub static kCFTypeDictionaryValueCallBacks: [usize; 5];
    pub static kCFBooleanTrue: Ref;
    pub fn CFRetain(value: Ref) -> Ref;
    pub fn CFRelease(value: Ref);
    pub fn CFNumberCreate(allocator: Ref, kind: i32, value: *const c_void) -> Ref;
    pub fn CFDictionaryCreate(
        allocator: Ref,
        keys: *const Ref,
        values: *const Ref,
        count: isize,
        keys_callback: Ref,
        values_callback: Ref,
    ) -> Ref;
}
#[link(name = "CoreVideo", kind = "framework")]
extern "C" {
    pub static kCVPixelBufferPixelFormatTypeKey: Ref;
    pub static kCVPixelBufferIOSurfacePropertiesKey: Ref;
    pub static kCVPixelBufferMetalCompatibilityKey: Ref;
    pub fn CVPixelBufferGetWidth(buffer: Ref) -> usize;
    pub fn CVPixelBufferGetHeight(buffer: Ref) -> usize;
    pub fn CVPixelBufferGetIOSurface(buffer: Ref) -> Ref;
}
#[link(name = "CoreMedia", kind = "framework")]
extern "C" {
    pub fn CMVideoFormatDescriptionCreateFromH264ParameterSets(
        allocator: Ref,
        count: usize,
        pointers: *const *const u8,
        sizes: *const usize,
        nal_length: i32,
        format: *mut Ref,
    ) -> i32;
    pub fn CMBlockBufferCreateWithMemoryBlock(
        allocator: Ref,
        memory: Ref,
        length: usize,
        block_allocator: Ref,
        custom: Ref,
        offset: usize,
        size: usize,
        flags: u32,
        block: *mut Ref,
    ) -> i32;
    pub fn CMBlockBufferReplaceDataBytes(
        source: *const u8,
        block: Ref,
        offset: usize,
        length: usize,
    ) -> i32;
    pub fn CMSampleBufferCreateReady(
        allocator: Ref,
        block: Ref,
        format: Ref,
        samples: isize,
        timing_count: isize,
        timing: *const Timing,
        size_count: isize,
        sizes: *const usize,
        sample: *mut Ref,
    ) -> i32;
}
#[link(name = "VideoToolbox", kind = "framework")]
extern "C" {
    pub fn VTDecompressionSessionCreate(
        allocator: Ref,
        format: Ref,
        specification: Ref,
        attributes: Ref,
        callback: *const Callback,
        session: *mut Ref,
    ) -> i32;
    pub fn VTDecompressionSessionDecodeFrame(
        session: Ref,
        sample: Ref,
        flags: u32,
        user: Ref,
        info: *mut u32,
    ) -> i32;
    pub fn VTDecompressionSessionWaitForAsynchronousFrames(session: Ref) -> i32;
    pub fn VTDecompressionSessionInvalidate(session: Ref);
}
