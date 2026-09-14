//! 批量调度并发引擎：基于 Tokio 异步运行时与 Arc<Semaphore> 硬件并发限流，
//! 防止多设备同时执行重度 I/O 时打崩宿主机 USB 控制器。

use std::sync::{Arc, OnceLock};
use std::time::Instant;
use serde::{Deserialize, Serialize};
use tokio::runtime::Runtime;
use tokio::sync::Semaphore;
use tokio::task::JoinSet;
use super::driver::DeviceDriver;

/// 单设备批量执行结果条目
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchDeviceResult {
    /// 目标设备标识
    pub serial: String,
    /// 是否执行成功
    pub success: bool,
    /// 成功时的命令标准输出
    pub output: String,
    /// 失败时的错误信息
    pub error: Option<String>,
    /// 执行耗时 (单位：毫秒)
    pub duration_ms: u64,
}

/// 批量调度并发引擎
pub struct BatchManager;

impl BatchManager {
    /// 默认 USB 控制器最大并发安全阈值 (经过硬件稳定性验证的推荐上限)
    pub const DEFAULT_MAX_CONCURRENCY: usize = 4;

    /// 获取全局 Tokio 多线程异步运行时
    pub fn runtime() -> &'static Runtime {
        static RUNTIME: OnceLock<Runtime> = OnceLock::new();
        RUNTIME.get_or_init(|| {
            tokio::runtime::Builder::new_multi_thread()
                .worker_threads(4)
                .thread_name("anydeck-tokio-dal")
                .enable_all()
                .build()
                .expect("Failed to initialize Tokio runtime for AnyDeck DAL")
        })
    }

    /// 异步执行批量 Shell 指令，使用信号量严格控制最大并发数
    pub async fn execute_shell_batch(
        drivers: Vec<Arc<dyn DeviceDriver>>,
        cmd: String,
        max_concurrency: usize,
    ) -> Vec<BatchDeviceResult> {
        let concurrency = if max_concurrency == 0 {
            Self::DEFAULT_MAX_CONCURRENCY
        } else {
            max_concurrency
        };

        let semaphore = Arc::new(Semaphore::new(concurrency));
        let mut join_set = JoinSet::new();

        for driver in drivers {
            let sem = semaphore.clone();
            let cmd = cmd.clone();
            let serial = driver.id().to_string();

            join_set.spawn(async move {
                // 请求信号量 Permit，若当前活跃任务已达上限则在 Tokio 队列中安全排队挂起
                let _permit = sem.acquire().await;
                let start_time = Instant::now();

                let res = driver.execute_shell(&cmd).await;
                let duration_ms = start_time.elapsed().as_millis() as u64;

                match res {
                    Ok(output) => BatchDeviceResult {
                        serial,
                        success: true,
                        output,
                        error: None,
                        duration_ms,
                    },
                    Err(err) => BatchDeviceResult {
                        serial,
                        success: false,
                        output: String::new(),
                        error: Some(err),
                        duration_ms,
                    },
                }
            });
        }

        let mut results = Vec::new();
        while let Some(res) = join_set.join_next().await {
            match res {
                Ok(item) => results.push(item),
                Err(e) => {
                    results.push(BatchDeviceResult {
                        serial: "unknown".into(),
                        success: false,
                        output: String::new(),
                        error: Some(format!("Tokio task failed: {e}")),
                        duration_ms: 0,
                    });
                }
            }
        }

        results
    }

    /// 同步入口：供 C-ABI 阻塞调用，进入全局 Tokio 异步运行时驱动任务完成
    pub fn execute_shell_batch_blocking(
        drivers: Vec<Arc<dyn DeviceDriver>>,
        cmd: String,
        max_concurrency: usize,
    ) -> Vec<BatchDeviceResult> {
        Self::runtime().block_on(Self::execute_shell_batch(drivers, cmd, max_concurrency))
    }
}
