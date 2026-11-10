//! H.264/AAC 无转码封装；媒体写入磁盘，仅缓存配置、单帧和有界启动音频。
use super::protocol::{nals, Event, Packet};
use mp4::{
    AacConfig, AudioObjectType, AvcConfig, ChannelConfig, Mp4Config, Mp4Sample, Mp4Writer,
    SampleFreqIndex, TrackConfig,
};
use std::{
    collections::VecDeque,
    fs::{File, OpenOptions},
    io::BufWriter,
    path::{Path, PathBuf},
    time::Instant,
};

const SCALE: u32 = 90_000;
const MAX_SAMPLES: u64 = 2_000_000;
struct Pending {
    sample: Mp4Sample,
    pts: u64,
}

pub struct Muxer {
    writer: Mp4Writer<BufWriter<File>>,
    pub partial: PathBuf,
    size: Option<(u16, u16)>,
    sps: Vec<u8>,
    pps: Vec<u8>,
    video_track: bool,
    audio_config: Option<AacConfig>,
    audio_track: bool,
    audio_disabled: bool,
    audio_wait: VecDeque<Packet>,
    origin: Option<u64>,
    started: Option<Instant>,
    ended: Option<std::time::Duration>,
    pending: [Option<Pending>; 2],
    offsets: [i32; 2],
    samples: u64,
}

impl Muxer {
    pub fn new(path: &Path) -> Result<Self, String> {
        if path.exists() {
            return Err("Recording destination already exists".into());
        }
        let partial = path.with_extension("partial.mp4");
        let file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&partial)
            .map_err(|e| e.to_string())?;
        let writer = Mp4Writer::write_start(
            BufWriter::new(file),
            &Mp4Config {
                major_brand: "isom".parse().unwrap(),
                minor_version: 512,
                compatible_brands: vec![
                    "isom".parse().unwrap(),
                    "avc1".parse().unwrap(),
                    "mp41".parse().unwrap(),
                ],
                timescale: SCALE,
            },
        )
        .map_err(|e| e.to_string())?;
        Ok(Self {
            writer,
            partial,
            size: None,
            sps: vec![],
            pps: vec![],
            video_track: false,
            audio_config: None,
            audio_track: false,
            audio_disabled: false,
            audio_wait: VecDeque::new(),
            origin: None,
            started: None,
            ended: None,
            pending: [None, None],
            offsets: [0, 0],
            samples: 0,
        })
    }

    pub fn ready(&self) -> bool {
        self.pending[0].is_some() && (self.audio_disabled || self.pending[1].is_some())
    }

    pub fn push(&mut self, event: Event) -> Result<(), String> {
        match event {
            Event::Size(w, h) => {
                if self.video_track && self.size != Some((w, h)) {
                    return Err("Recording dimensions changed; partial MP4 retained".into());
                }
                self.size = Some((w, h));
            }
            Event::AudioDisabled => self.audio_disabled = true,
            Event::Video(packet) => self.video(packet)?,
            Event::Audio(packet) => self.audio(packet)?,
        }
        Ok(())
    }

    fn video(&mut self, packet: Packet) -> Result<(), String> {
        let units = nals(&packet.data)?;
        let mut avcc = Vec::with_capacity(packet.data.len());
        let mut key = packet.key;
        for nal in units {
            match nal[0] & 31 {
                7 | 8 => {
                    let old = if nal[0] & 31 == 7 {
                        &mut self.sps
                    } else {
                        &mut self.pps
                    };
                    if self.video_track && old.as_slice() != nal {
                        return Err("H.264 configuration changed; partial MP4 retained".into());
                    }
                    *old = nal.to_vec();
                }
                5 => key = true,
                _ => {}
            }
            avcc.extend_from_slice(&(nal.len() as u32).to_be_bytes());
            avcc.extend_from_slice(nal);
        }
        if packet.config {
            return Ok(());
        }
        if !self.video_track {
            if !key {
                return Ok(());
            }
            let (width, height) = self.size.ok_or("Missing recording dimensions")?;
            if self.sps.len() < 4 || self.pps.is_empty() {
                return Err("Missing H.264 SPS/PPS".into());
            }
            let mut track = TrackConfig::from(AvcConfig {
                width,
                height,
                seq_param_set: self.sps.clone(),
                pic_param_set: self.pps.clone(),
            });
            track.timescale = SCALE;
            self.writer.add_track(&track).map_err(|e| e.to_string())?;
            self.video_track = true;
            self.origin = Some(packet.pts);
            self.started = Some(Instant::now());
        }
        self.sample(0, packet.pts, key, avcc)?;
        while let Some(audio) = self.audio_wait.pop_front() {
            self.audio(audio)?;
        }
        Ok(())
    }

    fn audio(&mut self, packet: Packet) -> Result<(), String> {
        if packet.config {
            let config = aac_config(&packet.data)?;
            if self.audio_track && self.audio_config.as_ref() != Some(&config) {
                return Err("AAC configuration changed".into());
            }
            self.audio_config = Some(config);
            return Ok(());
        }
        let Some(origin) = self.origin else {
            if self.audio_wait.len() >= 128 || packet.data.len() > 32 * 1024 {
                return Err("Recording audio startup buffer exceeded".into());
            }
            self.audio_wait.push_back(packet);
            return Ok(());
        };
        // 第一个视频关键帧之前的声音不进入文件，保持统一设备时间轴。
        if packet.pts < origin {
            return Ok(());
        }
        if !self.audio_track {
            let mut track =
                TrackConfig::from(self.audio_config.clone().ok_or("Missing AAC config")?);
            track.timescale = SCALE;
            self.writer.add_track(&track).map_err(|e| e.to_string())?;
            self.audio_track = true;
        }
        self.sample(1, packet.pts, true, packet.data)
    }

    fn sample(&mut self, track: usize, pts: u64, key: bool, bytes: Vec<u8>) -> Result<(), String> {
        if self.samples >= MAX_SAMPLES {
            return Err("Recording sample index limit reached".into());
        }
        let relative = pts
            .checked_sub(self.origin.unwrap())
            .ok_or("Recording timestamp regressed")?;
        let timestamp = (u128::from(relative) * u128::from(SCALE) / 1_000_000) as u64;
        if let Some(previous) = self.pending[track].as_ref() {
            let duration = timestamp
                .checked_sub(previous.pts)
                .filter(|d| *d > 0)
                .ok_or("Non-monotonic recording timestamp")?;
            let duration = duration
                .try_into()
                .map_err(|_| "Recording frame duration overflow")?;
            let mut previous = self.pending[track].take().unwrap();
            previous.sample.duration = duration;
            self.writer
                .write_sample(track as u32 + 1, &previous.sample)
                .map_err(|e| e.to_string())?;
        } else {
            self.offsets[track] = timestamp
                .try_into()
                .map_err(|_| "Recording track offset overflow")?;
        }
        self.pending[track] = Some(Pending {
            pts: timestamp,
            sample: Mp4Sample {
                start_time: timestamp,
                duration: 0,
                rendering_offset: self.offsets[track],
                is_sync: key,
                bytes: bytes.into(),
            },
        });
        self.samples += 1;
        Ok(())
    }

    /// 无论正常停止还是断线，都尝试写尾索引；只有成功路径才公布最终文件名。
    pub fn end_capture(&mut self) {
        self.ended = self.started.map(|start| start.elapsed());
    }

    /// ADB 清理可能较慢，不能将清理时间算入最后一帧时长。
    pub fn finish(mut self, path: &Path, success: bool) -> Result<(), String> {
        if !self.video_track {
            drop(self.writer);
            let _ = std::fs::remove_file(&self.partial);
            return Err("No video keyframe recorded".into());
        }
        let last_pts = self
            .pending
            .iter()
            .flatten()
            .map(|p| p.pts)
            .max()
            .unwrap_or(0);
        let elapsed = self
            .ended
            .or_else(|| self.started.map(|i| i.elapsed()))
            .map(|time| time.as_micros() * u128::from(SCALE) / 1_000_000)
            .unwrap_or(0);
        let end = last_pts
            .saturating_add(3000)
            .max(elapsed.min(u64::MAX as u128) as u64);
        for (index, pending) in self.pending.iter_mut().enumerate() {
            if let Some(mut packet) = pending.take() {
                packet.sample.duration = if index == 0 {
                    (end - packet.pts).min(u32::MAX as u64) as u32
                } else {
                    (1024 * u64::from(SCALE)
                        / u64::from(self.audio_config.as_ref().unwrap().freq_index.freq()))
                        as u32
                };
                self.writer
                    .write_sample(index as u32 + 1, &packet.sample)
                    .map_err(|e| e.to_string())?;
            }
        }
        self.writer.write_end().map_err(|e| e.to_string())?;
        let mut file = self.writer.into_writer();
        use std::io::Write;
        file.flush().map_err(|e| e.to_string())?;
        file.get_ref().sync_all().map_err(|e| e.to_string())?;
        drop(file);
        if success {
            publish(&self.partial, path)?;
        }
        Ok(())
    }
}

/// 使用系统排他重命名，避免覆盖停止期间新增的文件，也不要求卷支持 hard link。
#[cfg(target_os = "macos")]
fn publish(partial: &Path, path: &Path) -> Result<(), String> {
    use std::{
        ffi::{c_char, CString},
        os::unix::ffi::OsStrExt,
    };
    extern "C" {
        fn renamex_np(from: *const c_char, to: *const c_char, flags: u32) -> i32;
    }
    let from = CString::new(partial.as_os_str().as_bytes()).map_err(|e| e.to_string())?;
    let to = CString::new(path.as_os_str().as_bytes()).map_err(|e| e.to_string())?;
    // Darwin sys/stdio.h: RENAME_EXCL，自 macOS 10.12 提供。
    if unsafe { renamex_np(from.as_ptr(), to.as_ptr(), 0x00000004) } != 0 {
        return Err(std::io::Error::last_os_error().to_string());
    }
    Ok(())
}

#[cfg(not(target_os = "macos"))]
fn publish(partial: &Path, path: &Path) -> Result<(), String> {
    std::fs::hard_link(partial, path).map_err(|e| e.to_string())?;
    std::fs::remove_file(partial).map_err(|e| e.to_string())
}

fn aac_config(bytes: &[u8]) -> Result<AacConfig, String> {
    if bytes.len() < 2 || bytes[0] >> 3 != 2 {
        return Err("Expected AAC-LC AudioSpecificConfig".into());
    }
    let frequency = ((bytes[0] & 7) << 1) | (bytes[1] >> 7);
    let channels = (bytes[1] >> 3) & 15;
    if bytes[1] & 7 != 0 {
        return Err("Unsupported AAC frame configuration".into());
    }
    Ok(AacConfig {
        bitrate: 128000,
        profile: AudioObjectType::AacLowComplexity,
        freq_index: SampleFreqIndex::try_from(frequency).map_err(|e| e.to_string())?,
        chan_conf: ChannelConfig::try_from(channels).map_err(|e| e.to_string())?,
    })
}
