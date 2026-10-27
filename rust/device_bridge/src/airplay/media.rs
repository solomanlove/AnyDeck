//! HTTP 视频的有界命令快照；协议线程不等待 UI，播放器进度按代次回写。
use serde::Serialize;

#[derive(Default, Serialize)]
pub struct MediaState {
    pub generation: u64,
    pub revision: u64,
    pub seek_revision: u64,
    pub url: Option<String>,
    pub start: f64,
    pub rate: f64,
    #[serde(skip)]
    duration: f64,
    #[serde(skip)]
    position: f64,
    #[serde(skip)]
    actual_rate: f64,
    #[serde(skip)]
    ready: bool,
    #[serde(skip)]
    ended: bool,
}

impl MediaState {
    /// 1=播放，2=跳转，3=速率，4=结束；只保存最后的目标状态，不累计事件队列。
    pub fn command(&mut self, command: i32, url: Option<&str>, value: f64) -> Result<(), &'static str> {
        if !value.is_finite() || value < 0.0 { return Err("Invalid AirPlay media value"); }
        match command {
            1 => {
                let url = url.ok_or("Missing AirPlay media URL")?;
                let host = url.strip_prefix("https://").or_else(|| url.strip_prefix("http://"))
                    .and_then(|s| s.split(['/', '?', '#']).next()).unwrap_or("");
                if url.len() > 16384 || host.is_empty() || url.chars().any(|c| c.is_whitespace() || c.is_control()) {
                    return Err("AirPlay media requires a bounded HTTP(S) URL");
                }
                self.generation += 1;
                self.url = Some(url.to_owned());
                self.start = value;
                self.seek_revision += 1;
                self.rate = 1.0;
                self.duration = 0.0;
                self.position = value;
                self.actual_rate = 0.0;
                self.ready = false;
                self.ended = false;
            }
            2 if self.url.is_some() => {
                self.start = value;
                self.seek_revision += 1;
            }
            3 if self.url.is_some() && value <= 4.0 => self.rate = value,
            4 if self.url.is_some() => {
                self.url = None;
                self.actual_rate = 0.0;
                self.ready = false;
                self.ended = true;
            }
            _ => return Ok(()),
        }
        self.revision += 1;
        Ok(())
    }

    /// 旧媒体异步回调不能覆盖新媒体；state: 0=加载，1=就绪，2=结束/失败。
    pub fn update(&mut self, generation: u64, duration: f64, position: f64, rate: f64, state: u8) {
        if generation != self.generation || self.url.is_none() { return; }
        if ![duration, position, rate].iter().all(|v| v.is_finite() && *v >= 0.0) { return; }
        self.duration = duration;
        self.position = position;
        self.actual_rate = rate;
        self.ready = state == 1;
        self.ended = state == 2;
        if self.ended { let _ = self.command(4, None, 0.0); }
    }

    pub fn playback_info(&self) -> [f64; 5] {
        [self.duration, self.position, self.actual_rate, u8::from(self.ready) as f64, u8::from(self.ended) as f64]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn switch_seek_pause_and_stale_progress() {
        let mut state = MediaState::default();
        state.command(1, Some("https://example.test/a.m3u8"), 3.0).unwrap();
        let old = state.generation;
        state.update(old, 100.0, 4.0, 1.0, 1);
        assert_eq!(state.playback_info(), [100.0, 4.0, 1.0, 1.0, 0.0]);
        state.command(2, None, 20.0).unwrap();
        state.command(3, None, 0.0).unwrap();
        assert_eq!((state.start, state.rate), (20.0, 0.0));
        state.command(1, Some("https://example.test/b.mp4"), 0.0).unwrap();
        state.update(old, 100.0, 5.0, 0.0, 2);
        assert!(state.url.as_ref().unwrap().ends_with("b.mp4"));
        state.update(state.generation, 50.0, 50.0, 0.0, 2);
        assert!(state.url.is_none());
        assert_eq!(state.playback_info()[4], 1.0);
        let revision = state.revision;
        state.command(4, None, 0.0).unwrap();
        assert_eq!(state.revision, revision);
    }

    #[test]
    fn rejects_invalid_or_unbounded_commands_without_changing_state() {
        let mut state = MediaState::default();
        for url in ["file:///etc/hosts".to_owned(), "http://".to_owned(), format!("https://example.test/{}", "a".repeat(16384))] {
            assert!(state.command(1, Some(&url), 0.0).is_err());
        }
        assert!(state.command(1, Some("https://example.test/a.mp4"), f64::NAN).is_err());
        assert_eq!(state.revision, 0);
        assert!(state.url.is_none());
    }
}
