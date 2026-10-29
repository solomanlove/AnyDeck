//! PCM 播放恢复：接收线程持续排空 socket，输出失败时仅重建本机播放器。
use std::time::{Duration, Instant};

const RETRY_DELAY: Duration = Duration::from_millis(500);

pub(crate) trait PcmOutput {
    fn mute(&mut self, muted: bool) -> Result<(), String>;
    fn write(&mut self, pcm: &[u8]) -> Result<(), String>;
}

/// 输出创建、音量或入队失败均可恢复；固定退避避免音频设备不可用时逐包重建。
pub(crate) struct PcmPlayback<P, F> {
    output: Option<P>,
    create: F,
    applied_mute: Option<bool>,
    retry_at: Instant,
    last_pcm_at: Option<Instant>,
}

impl<P: PcmOutput, F: FnMut() -> Result<P, String>> PcmPlayback<P, F> {
    pub(crate) fn new(create: F) -> Self {
        Self {
            output: None,
            create,
            applied_mute: None,
            retry_at: Instant::now(),
            last_pcm_at: None,
        }
    }

    /// 独立音频入口保留首次创建失败的错误语义，后续播放共享恢复逻辑。
    pub(crate) fn with_output(output: P, create: F) -> Self {
        let mut player = Self::new(create);
        player.output = Some(output);
        player
    }

    pub(crate) fn write(&mut self, pcm: &[u8], muted: bool) -> bool {
        self.write_at(pcm, muted, Instant::now())
    }

    fn write_at(&mut self, pcm: &[u8], muted: bool, now: Instant) -> bool {
        if pcm.is_empty() {
            return false;
        }
        // 网络长停顿/暂停后丢弃旧队列的积压，以最新 PCM 恢复，避免永久静音。
        if self
            .last_pcm_at
            .is_some_and(|last| now.duration_since(last) > Duration::from_millis(1500))
        {
            self.output = None;
            self.applied_mute = None;
        }
        self.last_pcm_at = Some(now);
        // 最多尝试当前队列和一次重建；每次创建后至少间隔 500ms 才允许再次创建。
        for _ in 0..2 {
            if self.output.is_none() {
                if now < self.retry_at {
                    return false;
                }
                self.retry_at = now + RETRY_DELAY;
                match (self.create)() {
                    Ok(output) => {
                        self.output = Some(output);
                        self.applied_mute = None;
                    }
                    Err(error) => {
                        eprintln!(
                            "[Android Audio] output creation failed: {error}; retry in 500ms"
                        );
                        return false;
                    }
                }
            }
            let output = self.output.as_mut().unwrap();
            let result = if self.applied_mute != Some(muted) {
                output.mute(muted)
            } else {
                Ok(())
            }
            .and_then(|_| {
                self.applied_mute = Some(muted);
                output.write(pcm)
            });
            match result {
                Ok(()) => return true,
                Err(error) => {
                    // 先 Dispose 旧队列，确保回调结束后再创建新队列，并重新应用静音状态。
                    self.output = None;
                    self.applied_mute = None;
                    eprintln!("[Android Audio] rebuilding output: {error}");
                }
            }
        }
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{cell::RefCell, rc::Rc};

    #[derive(Default)]
    struct Events {
        created: usize,
        dropped: usize,
        fail_create: bool,
        fail_write: bool,
        fail_mute: bool,
        writes: Vec<Vec<u8>>,
        mutes: Vec<bool>,
    }
    struct Output(Rc<RefCell<Events>>);
    impl PcmOutput for Output {
        fn mute(&mut self, muted: bool) -> Result<(), String> {
            let mut events = self.0.borrow_mut();
            events.mutes.push(muted);
            if events.fail_mute {
                Err("volume failed".into())
            } else {
                Ok(())
            }
        }
        fn write(&mut self, pcm: &[u8]) -> Result<(), String> {
            let mut events = self.0.borrow_mut();
            if events.fail_write {
                return Err("queue stalled".into());
            }
            events.writes.push(pcm.to_vec());
            Ok(())
        }
    }
    impl Drop for Output {
        fn drop(&mut self) {
            self.0.borrow_mut().dropped += 1;
        }
    }
    fn create(events: &Rc<RefCell<Events>>) -> Result<Output, String> {
        let mut state = events.borrow_mut();
        state.created += 1;
        if state.fail_create {
            Err("device unavailable".into())
        } else {
            Ok(Output(events.clone()))
        }
    }

    #[test]
    fn output_failure_rebuilds_without_reconnecting_and_preserves_mute() {
        let events = Rc::new(RefCell::new(Events::default()));
        let mut player = PcmPlayback::new(|| create(&events));
        let now = Instant::now();
        assert!(player.write_at(&[1, 2, 3, 4], true, now));
        events.borrow_mut().fail_write = true;
        assert!(!player.write_at(&[5; 4], true, now + Duration::from_millis(100)));
        assert_eq!(events.borrow().dropped, 1);
        events.borrow_mut().fail_write = false;
        assert!(player.write_at(&[6; 4], true, now + RETRY_DELAY));
        assert_eq!(events.borrow().created, 2);
        assert_eq!(events.borrow().mutes, vec![true, true]);
        assert_eq!(events.borrow().writes, vec![vec![1, 2, 3, 4], vec![6; 4]]);
    }

    #[test]
    fn unavailable_output_retries_at_bounded_rate_and_recovers() {
        let events = Rc::new(RefCell::new(Events {
            fail_create: true,
            ..Events::default()
        }));
        let mut player = PcmPlayback::new(|| create(&events));
        let now = Instant::now();
        for ms in 0..500 {
            assert!(!player.write_at(&[0; 4], false, now + Duration::from_millis(ms)));
        }
        assert_eq!(events.borrow().created, 1);
        events.borrow_mut().fail_create = false;
        assert!(player.write_at(&[0; 4], false, now + RETRY_DELAY));
        assert_eq!(events.borrow().created, 2);
    }

    #[test]
    fn persistent_enqueue_failure_does_not_rebuild_on_every_packet() {
        let events = Rc::new(RefCell::new(Events {
            fail_write: true,
            ..Events::default()
        }));
        let mut player = PcmPlayback::new(|| create(&events));
        let now = Instant::now();
        for ms in 0..1000 {
            assert!(!player.write_at(&[0; 4], false, now + Duration::from_millis(ms)));
        }
        assert_eq!(events.borrow().created, 2);
        assert_eq!(events.borrow().dropped, 2);
    }

    #[test]
    fn volume_failure_is_retried_and_new_output_uses_latest_focus_state() {
        let events = Rc::new(RefCell::new(Events {
            fail_mute: true,
            ..Events::default()
        }));
        let mut player = PcmPlayback::new(|| create(&events));
        let now = Instant::now();
        assert!(!player.write_at(&[0; 4], true, now));
        events.borrow_mut().fail_mute = false;
        assert!(player.write_at(&[0; 4], false, now + RETRY_DELAY));
        assert_eq!(events.borrow().mutes, vec![true, false]);
    }

    #[test]
    fn healthy_stream_and_mute_changes_reuse_single_output() {
        let events = Rc::new(RefCell::new(Events::default()));
        let mut player = PcmPlayback::new(|| create(&events));
        let now = Instant::now();
        for ms in 0..10000 {
            assert!(player.write_at(&[0; 4], ms >= 5000, now + Duration::from_millis(ms)));
        }
        assert_eq!(events.borrow().created, 1);
        assert_eq!(events.borrow().mutes, vec![false, true]);
    }
    #[test]
    fn long_pause_rebuilds_output_with_latest_mute() {
        let events = Rc::new(RefCell::new(Events::default()));
        let mut player = PcmPlayback::new(|| create(&events));
        let now = Instant::now();
        assert!(player.write_at(&[0; 4], false, now));
        assert!(player.write_at(&[1; 4], true, now + Duration::from_secs(2)));
        assert_eq!(events.borrow().created, 2);
        assert_eq!(events.borrow().dropped, 1);
        assert_eq!(events.borrow().mutes, vec![false, true]);
    }
}
