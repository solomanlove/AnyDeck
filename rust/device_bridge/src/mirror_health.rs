//! 按媒体 PTS 与本机单调时钟估算接收积压；无需对时，不以静态画面 FPS 判弱网。
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Mutex,
};
use std::time::{Duration, Instant};

#[derive(Default)]
pub(crate) struct MirrorHealth {
    video: Mutex<Option<(Instant, u32)>>,
    pub(crate) audio_failed: AtomicBool,
}

impl MirrorHealth {
    pub(crate) fn record_video(&self, lag_ms: u32) {
        if let Ok(mut video) = self.video.lock() {
            *video = Some((Instant::now(), lag_ms));
        }
    }

    fn snapshot(&self) -> u64 {
        // 静止/暂停后不重复消费旧的拥塞样本。
        let lag = self
            .video
            .lock()
            .ok()
            .and_then(|video| *video)
            .filter(|(at, _)| at.elapsed() < Duration::from_millis(1500))
            .map(|(_, lag)| lag)
            .unwrap_or(0);
        u64::from(lag) | (u64::from(self.audio_failed.load(Ordering::Acquire)) << 32)
    }
}

/// 低 32 位为新增接收延迟 ms，bit 32 为已工作音频流意外结束；旧客户端可忽略。
#[no_mangle]
pub extern "C" fn anydeck_mirror_health(id: u64) -> u64 {
    crate::session(id).map(|s| s.health.snapshot()).unwrap_or(0)
}

#[derive(Default)]
pub(crate) struct VideoLag {
    origin: Option<(u64, Instant)>,
    previous_pts: u64,
    minimum_offset_us: i128,
}

impl VideoLag {
    pub(crate) fn observe(&mut self, pts: u64, now: Instant) -> u32 {
        if self.origin.is_none() || pts < self.previous_pts {
            self.origin = Some((pts, now));
            self.minimum_offset_us = 0;
        }
        self.previous_pts = pts;
        let (base_pts, base_time) = self.origin.unwrap();
        let offset = now.duration_since(base_time).as_micros() as i128 - i128::from(pts - base_pts);
        self.minimum_offset_us = self.minimum_offset_us.min(offset);
        ((offset - self.minimum_offset_us) / 1000).min(i128::from(u32::MAX)) as u32
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn static_screen_or_pause_is_not_network_congestion() {
        let mut lag = VideoLag::default();
        let now = Instant::now();
        assert_eq!(lag.observe(9_000_000, now), 0);
        assert_eq!(lag.observe(19_000_000, now + Duration::from_secs(10)), 0);
    }

    #[test]
    fn slow_delivery_accumulates_lag_and_catching_up_clears_it() {
        let mut lag = VideoLag::default();
        let now = Instant::now();
        lag.observe(0, now);
        assert_eq!(
            lag.observe(1_000_000, now + Duration::from_millis(1400)),
            400
        );
        assert_eq!(
            lag.observe(2_000_000, now + Duration::from_millis(2800)),
            800
        );
        assert_eq!(lag.observe(3_000_000, now + Duration::from_millis(3000)), 0);
    }

    #[test]
    fn pts_reset_and_clock_offset_do_not_create_false_lag() {
        let mut lag = VideoLag::default();
        let now = Instant::now();
        lag.observe(1_000_000, now);
        assert_eq!(lag.observe(10, now + Duration::from_secs(1)), 0);
        assert_eq!(lag.observe(1_000_010, now + Duration::from_secs(2)), 0);
    }

    #[test]
    fn stale_video_lag_expires_but_audio_failure_persists() {
        let health = MirrorHealth::default();
        health.record_video(500);
        assert_eq!(health.snapshot(), 500);
        *health.video.lock().unwrap() = Some((Instant::now() - Duration::from_secs(2), 500));
        health.audio_failed.store(true, Ordering::Release);
        assert_eq!(health.snapshot(), 1 << 32);
    }
}
