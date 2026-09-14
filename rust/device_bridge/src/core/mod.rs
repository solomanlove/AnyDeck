//! 统一设备抽象层 (Device Abstraction Layer, DAL) 与并发控制引擎
pub mod driver;
pub mod android;
pub mod harmony;
pub mod ios;
pub mod batch;
pub mod ring_buffer;

pub use driver::{DeviceDriver, DevicePlatform};
pub use android::AndroidDriver;
pub use harmony::HarmonyDriver;
pub use ios::IosDriver;
pub use batch::{BatchManager, BatchDeviceResult};
pub use ring_buffer::{LogRingBuffer, LogEntry};

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;
    use std::time::Duration;
    use async_trait::async_trait;

    struct MockDriver {
        serial: String,
        active_counter: Arc<AtomicUsize>,
        max_seen: Arc<AtomicUsize>,
    }

    #[async_trait]
    impl DeviceDriver for MockDriver {
        fn id(&self) -> &str {
            &self.serial
        }

        fn platform(&self) -> DevicePlatform {
            DevicePlatform::Android
        }

        async fn execute_shell(&self, cmd: &str) -> Result<String, String> {
            let current = self.active_counter.fetch_add(1, Ordering::SeqCst) + 1;
            let mut prev_max = self.max_seen.load(Ordering::SeqCst);
            while current > prev_max {
                match self.max_seen.compare_exchange_weak(
                    prev_max,
                    current,
                    Ordering::SeqCst,
                    Ordering::SeqCst,
                ) {
                    Ok(_) => break,
                    Err(actual) => prev_max = actual,
                }
            }

            tokio::time::sleep(Duration::from_millis(50)).await;
            self.active_counter.fetch_sub(1, Ordering::SeqCst);

            Ok(format!("{}: {}", self.serial, cmd))
        }

        async fn take_screenshot(&self) -> Result<Vec<u8>, String> {
            Ok(vec![0x89, 0x50, 0x4E, 0x47])
        }

        async fn push_file(&self, _local: &str, _remote: &str) -> Result<(), String> {
            Ok(())
        }
    }

    #[tokio::test]
    async fn test_batch_manager_semaphore_concurrency() {
        let active = Arc::new(AtomicUsize::new(0));
        let max_seen = Arc::new(AtomicUsize::new(0));

        let drivers: Vec<Arc<dyn DeviceDriver>> = (0..6)
            .map(|i| {
                Arc::new(MockDriver {
                    serial: format!("device_{i}"),
                    active_counter: active.clone(),
                    max_seen: max_seen.clone(),
                }) as Arc<dyn DeviceDriver>
            })
            .collect();

        // 限制最大并发数为 2
        let results = BatchManager::execute_shell_batch(drivers, "echo ping".into(), 2).await;

        assert_eq!(results.len(), 6);
        for res in results {
            assert!(res.success);
            assert!(res.output.contains("echo ping"));
        }

        // 验证并发未突破信号量限制 2
        assert!(max_seen.load(Ordering::SeqCst) <= 2);
    }

    #[test]
    fn test_log_ring_buffer_fifo_and_query() {
        let rb = LogRingBuffer::new(5);
        for i in 0..8 {
            rb.push(LogEntry {
                id: 0,
                timestamp: "12-31 12:00:00".into(),
                level: if i % 2 == 0 { 3 } else { 5 }, // 3=Debug, 5=Warn
                pid: 1000 + i as u32,
                tid: 2000,
                tag: format!("Tag_{}", i),
                message: format!("Log message {i}"),
            });
        }

        assert_eq!(rb.len(), 5);

        // 仅查询 level >= 4 (Warn)
        let warns = rb.query(4, None, None, None, 0, 10);
        for entry in &warns {
            assert!(entry.level >= 4);
        }

        // 关键词过滤
        let filtered = rb.query(0, None, None, Some("message 7"), 0, 10);
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].tag, "Tag_7");
    }
}
