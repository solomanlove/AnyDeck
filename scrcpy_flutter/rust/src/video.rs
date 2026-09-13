//! H.264 Annex-B → AVCC → VideoToolbox；输出 CVPixelBufferRef 直接供 Flutter Texture 零拷贝渲染。
use crate::video_ffi::*;
use std::ptr;
use std::sync::{Arc, Mutex};

/// 保存最新解码出的 CVPixelBufferRef 句柄并管理其引用计数。
#[derive(Default)]
pub struct Frame(pub Mutex<usize>);

impl Frame {
    /// 拷贝并增加 CVPixelBuffer 引用计数，由调用方负责在完成渲染或传递后 CFRelease。
    pub fn copy(&self) -> Ref {
        let Ok(frame) = self.0.lock() else {
            return ptr::null_mut();
        };
        if *frame == 0 {
            ptr::null_mut()
        } else {
            unsafe { CFRetain(*frame as Ref) }
        }
    }

    /// 获取当前最新帧的实际宽高。
    pub fn dimensions(&self) -> (u32, u32) {
        let Ok(frame) = self.0.lock() else {
            return (0, 0);
        };
        if *frame == 0 {
            return (0, 0);
        }
        unsafe {
            (
                CVPixelBufferGetWidth(*frame as Ref) as u32,
                CVPixelBufferGetHeight(*frame as Ref) as u32,
            )
        }
    }
}

impl Drop for Frame {
    fn drop(&mut self) {
        if let Ok(frame) = self.0.lock() {
            if *frame != 0 {
                unsafe {
                    CFRelease(*frame as Ref);
                }
            }
        }
    }
}

/// VideoToolbox 解码完成异步/同步回调函数。
extern "C" fn output(
    user: Ref,
    _source: Ref,
    status: i32,
    _flags: u32,
    image: Ref,
    _pts: Time,
    _duration: Time,
) {
    if status != 0 || image.is_null() {
        return;
    }
    let frame = unsafe { &*(user as *const Frame) };
    if let Ok(mut latest) = frame.0.lock() {
        unsafe {
            CFRetain(image);
            if *latest != 0 {
                CFRelease(*latest as Ref);
            }
        }
        *latest = image as usize;
    }
}

/// VideoToolbox H.264 硬件解码器。
pub struct Decoder {
    session: Ref,
    format: Ref,
    sps: Vec<u8>,
    pps: Vec<u8>,
    frame: Arc<Frame>,
}

impl Decoder {
    pub fn new(frame: Arc<Frame>) -> Self {
        Self {
            session: ptr::null_mut(),
            format: ptr::null_mut(),
            sps: Vec::new(),
            pps: Vec::new(),
            frame,
        }
    }

    pub fn frame(&self) -> &Arc<Frame> {
        &self.frame
    }

    fn reset(&mut self) {
        unsafe {
            if !self.session.is_null() {
                VTDecompressionSessionWaitForAsynchronousFrames(self.session);
                VTDecompressionSessionInvalidate(self.session);
                CFRelease(self.session);
                self.session = ptr::null_mut();
            }
            if !self.format.is_null() {
                CFRelease(self.format);
                self.format = ptr::null_mut();
            }
        }
    }

    fn configure(&mut self) -> Result<(), String> {
        self.reset();
        let pointers = [self.sps.as_ptr(), self.pps.as_ptr()];
        let sizes = [self.sps.len(), self.pps.len()];
        unsafe {
            if CMVideoFormatDescriptionCreateFromH264ParameterSets(
                ptr::null_mut(),
                2,
                pointers.as_ptr(),
                sizes.as_ptr(),
                4,
                &mut self.format,
            ) != 0
            {
                return Err("Invalid H264 parameter sets".into());
            }
            // Flutter macOS Texture 支持 32BGRA 显存纹理，直接由 Metal 读取。
            let bgra = u32::from_be_bytes(*b"BGRA");
            let number = CFNumberCreate(ptr::null_mut(), 3, &bgra as *const u32 as *const _);
            let keys = [kCVPixelBufferPixelFormatTypeKey];
            let values = [number];
            let attributes = CFDictionaryCreate(
                ptr::null_mut(),
                keys.as_ptr(),
                values.as_ptr(),
                1,
                kCFTypeDictionaryKeyCallBacks.as_ptr() as Ref,
                kCFTypeDictionaryValueCallBacks.as_ptr() as Ref,
            );
            let callback = Callback {
                function: output,
                user: Arc::as_ptr(&self.frame) as Ref,
            };
            let result = VTDecompressionSessionCreate(
                ptr::null_mut(),
                self.format,
                ptr::null_mut(),
                attributes,
                &callback,
                &mut self.session,
            );
            CFRelease(attributes);
            CFRelease(number);
            if result != 0 {
                return Err(format!("VideoToolbox initialization failed: {result}"));
            }
        }
        Ok(())
    }

    /// 解码单帧或关键帧码流数据包。
    pub fn decode(&mut self, packet: &[u8], pts: u64) -> Result<(), String> {
        let nals = annex_b(packet)?;
        let mut changed = false;
        let mut avcc = Vec::with_capacity(packet.len());
        let mut picture = false;
        for nal in nals {
            match nal[0] & 31 {
                7 => {
                    if self.sps != nal {
                        self.sps = nal.to_vec();
                        changed = true;
                    }
                }
                8 => {
                    if self.pps != nal {
                        self.pps = nal.to_vec();
                        changed = true;
                    }
                }
                _ => {
                    if matches!(nal[0] & 31, 1..=5) {
                        picture = true;
                    }
                    avcc.extend_from_slice(&(nal.len() as u32).to_be_bytes());
                    avcc.extend_from_slice(nal);
                }
            }
        }
        if (changed || self.session.is_null()) && !self.sps.is_empty() && !self.pps.is_empty() {
            self.configure()?;
        }
        if !picture {
            return Ok(());
        }
        if self.session.is_null() {
            return Err("Missing H264 configuration".into());
        }
        let invalid = Time {
            value: 0,
            scale: 0,
            flags: 0,
            epoch: 0,
        };
        let timing = Timing {
            duration: invalid,
            presentation: Time {
                value: pts as i64,
                scale: 1_000_000,
                flags: 1,
                epoch: 0,
            },
            decode: invalid,
        };
        unsafe {
            let mut block = ptr::null_mut();
            if CMBlockBufferCreateWithMemoryBlock(
                ptr::null_mut(),
                ptr::null_mut(),
                avcc.len(),
                ptr::null_mut(),
                ptr::null_mut(),
                0,
                avcc.len(),
                0,
                &mut block,
            ) != 0
            {
                return Err("Video block allocation failed".into());
            }
            let copied = CMBlockBufferReplaceDataBytes(avcc.as_ptr(), block, 0, avcc.len());
            let mut sample = ptr::null_mut();
            let length = avcc.len();
            let created = if copied == 0 {
                CMSampleBufferCreateReady(
                    ptr::null_mut(),
                    block,
                    self.format,
                    1,
                    1,
                    &timing,
                    1,
                    &length,
                    &mut sample,
                )
            } else {
                copied
            };
            CFRelease(block);
            if created != 0 {
                return Err("Video sample creation failed".into());
            }
            let result = VTDecompressionSessionDecodeFrame(
                self.session,
                sample,
                0,
                ptr::null_mut(),
                ptr::null_mut(),
            );
            CFRelease(sample);
            if result != 0 {
                return Err(format!("Video decode failed: {result}"));
            }
        }
        Ok(())
    }
}

impl Drop for Decoder {
    fn drop(&mut self) {
        self.reset();
    }
}

/// 解析 Annex-B 码流中的 NALU 切片。
fn annex_b(bytes: &[u8]) -> Result<Vec<&[u8]>, String> {
    let mut starts = Vec::new();
    let mut i = 0;
    while i + 3 <= bytes.len() {
        let length = if bytes[i..].starts_with(&[0, 0, 0, 1]) {
            4
        } else if bytes[i..].starts_with(&[0, 0, 1]) {
            3
        } else {
            i += 1;
            continue;
        };
        starts.push((i, i + length));
        i += length;
    }
    if starts.is_empty() {
        return Err("Invalid Annex-B packet".into());
    }
    let mut result = Vec::new();
    for (index, (_, start)) in starts.iter().enumerate() {
        let end = starts
            .get(index + 1)
            .map(|entry| entry.0)
            .unwrap_or(bytes.len());
        if *start < end {
            result.push(&bytes[*start..end]);
        }
    }
    Ok(result)
}
