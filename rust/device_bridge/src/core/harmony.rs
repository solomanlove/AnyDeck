//! 鸿蒙 (HarmonyOS) 设备驱动实现：基于官方 HDC (HarmonyOS Device Connector) 进程管道通信
use std::path::PathBuf;
use std::sync::OnceLock;
use std::time::Duration;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use super::driver::{DeviceDriver, DevicePlatform};

/// 鸿蒙设备目标条目
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct HarmonyTarget {
    /// 目标设备标识符 (如 `127.0.0.1:10178` 或 USB 序列号)
    pub serial: String,
    /// 连接传输类型 (`USB` 或 `TCP`)
    pub transport: String,
    /// 设备在线状态 (`Connected` 或 `Offline`)
    pub status: String,
}

/// 探测宿主机环境中的 hdc 可执行二进制文件绝对路径
pub fn find_hdc_path() -> Result<PathBuf, String> {
    static CACHED_HDC: OnceLock<Option<PathBuf>> = OnceLock::new();

    let path_opt = CACHED_HDC.get_or_init(|| {
        // 1. 优先检查环境变量 HDC_PATH / OHOS_SDK_HOME / HUAWEI_SDK_HOME
        if let Ok(env_path) = std::env::var("HDC_PATH") {
            let p = PathBuf::from(env_path);
            if p.is_file() {
                return Some(p);
            }
        }
        if let Ok(sdk_home) = std::env::var("OHOS_SDK_HOME") {
            let p = PathBuf::from(sdk_home).join("toolchains").join("hdc");
            if p.is_file() {
                return Some(p);
            }
        }
        if let Ok(sdk_home) = std::env::var("HUAWEI_SDK_HOME") {
            let p = PathBuf::from(sdk_home).join("toolchains").join("hdc");
            if p.is_file() {
                return Some(p);
            }
        }

        // 2. 检查常见默认安装路径 (DevEco-Studio / 用户目录 / Homebrew)
        let home = std::env::var("HOME").unwrap_or_default();
        let candidates = [
            format!("{home}/Library/Huawei/Sdk/openharmony/toolchains/hdc"),
            "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc".to_string(),
            "/Applications/DevEco_Testing_for_App.app/Contents/Resources/app/resources/bin/hdc".to_string(),
            "/opt/homebrew/bin/hdc".to_string(),
            "/usr/local/bin/hdc".to_string(),
        ];

        for c in &candidates {
            let p = PathBuf::from(c);
            if p.is_file() {
                return Some(p);
            }
        }

        // 3. 尝试 PATH 中的 which hdc
        if let Ok(output) = std::process::Command::new("/usr/bin/which").arg("hdc").output() {
            if output.status.success() {
                let stdout_str = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !stdout_str.is_empty() {
                    let p = PathBuf::from(stdout_str);
                    if p.is_file() {
                        return Some(p);
                    }
                }
            }
        }

        None
    });

    path_opt.clone().ok_or_else(|| {
        "hdc executable not found. Please install OpenHarmony SDK or DevEco Studio, or set HDC_PATH environment variable.".to_string()
    })
}

/// 鸿蒙平台专用设备驱动 (基于官方 HDC 通信管道)
pub struct HarmonyDriver {
    target: String,
}

impl HarmonyDriver {
    /// 创建指定目标标识的鸿蒙设备驱动实例
    pub fn new(target: impl Into<String>) -> Self {
        Self {
            target: target.into(),
        }
    }

    /// 底层通用执行 HDC 命令，带异步超时与错误捕获
    pub async fn run_hdc_cmd(args: &[&str], timeout_duration: Duration) -> Result<String, String> {
        let hdc_path = find_hdc_path()?;
        let child = tokio::process::Command::new(hdc_path)
            .args(args)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .map_err(|e| format!("Failed to spawn hdc process: {e}"))?;

        let output_fut = child.wait_with_output();
        let output = tokio::time::timeout(timeout_duration, output_fut)
            .await
            .map_err(|_| format!("hdc command timed out after {timeout_duration:?}"))?
            .map_err(|e| format!("Failed to wait for hdc process: {e}"))?;

        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();

        if !output.status.success() {
            let err_msg = if !stderr.trim().is_empty() {
                stderr.trim()
            } else if !stdout.trim().is_empty() {
                stdout.trim()
            } else {
                "Unknown HDC error (non-zero exit code)"
            };
            return Err(err_msg.to_string());
        }

        // 检查 HDC 输出常见错误标记（包括通信通道握手失败提示）
        let is_err = stdout.contains("[Fail]")
            || stderr.contains("[Fail]")
            || stdout.contains("[E0")
            || stderr.contains("[E0")
            || stdout.contains("The communication channel is being established")
            || stdout.contains("Please wait for several seconds");
        if is_err {
            let msg = if !stderr.trim().is_empty() {
                stderr.trim()
            } else {
                stdout.trim()
            };
            return Err(msg.to_string());
        }

        Ok(stdout)
    }

    /// 查询已连接的鸿蒙设备列表 (解析 `hdc list targets -v` 或降级解析 `hdc list targets`)
    pub async fn list_targets() -> Result<Vec<HarmonyTarget>, String> {
        let output_res = Self::run_hdc_cmd(&["list", "targets", "-v"], Duration::from_secs(10)).await;
        let raw_output = match output_res {
            Ok(out) => out,
            Err(_) => Self::run_hdc_cmd(&["list", "targets"], Duration::from_secs(10)).await?,
        };

        let mut targets = Vec::new();
        for line in raw_output.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty()
                || trimmed == "[Empty]"
                || trimmed.starts_with('[')
                || trimmed.contains("Please wait for several")
            {
                continue;
            }
            let parts: Vec<&str> = trimmed.split_whitespace().collect();
            if let Some(&first) = parts.first() {
                let transport = if parts.len() >= 2 {
                    parts[1]
                } else if first.contains(':') {
                    "TCP"
                } else {
                    "USB"
                };
                let status = if parts.len() >= 3 {
                    parts[2]
                } else {
                    "Connected"
                };
                targets.push(HarmonyTarget {
                    serial: first.to_string(),
                    transport: transport.to_string(),
                    status: status.to_string(),
                });
            }
        }
        Ok(targets)
    }

    /// 从鸿蒙设备拉取文件至本地
    pub async fn pull_file(&self, remote: &str, local: &str) -> Result<(), String> {
        Self::run_hdc_cmd(
            &["-t", &self.target, "file", "recv", remote, local],
            Duration::from_secs(300),
        )
        .await?;
        Ok(())
    }

    /// 通过 uinput 注入触控点击事件
    pub async fn uinput_click(&self, x: i32, y: i32) -> Result<(), String> {
        let cmd = format!("uinput -T -c {x} {y}");
        self.execute_shell(&cmd).await?;
        Ok(())
    }

    /// 通过 uinput 注入滑动事件
    pub async fn uinput_swipe(
        &self,
        x1: i32,
        y1: i32,
        x2: i32,
        y2: i32,
        duration_ms: u32,
    ) -> Result<(), String> {
        let cmd = format!("uinput -T -m {x1} {y1} {x2} {y2} {duration_ms}");
        self.execute_shell(&cmd).await?;
        Ok(())
    }

    /// 通过 uinput 注入手指按下事件
    pub async fn uinput_touch_down(&self, x: i32, y: i32) -> Result<(), String> {
        let cmd = format!("uinput -T -d {x} {y}");
        self.execute_shell(&cmd).await?;
        Ok(())
    }

    /// 通过 uinput 注入手指抬起事件
    pub async fn uinput_touch_up(&self, x: i32, y: i32) -> Result<(), String> {
        let cmd = format!("uinput -T -u {x} {y}");
        self.execute_shell(&cmd).await?;
        Ok(())
    }
}

#[async_trait]
impl DeviceDriver for HarmonyDriver {
    fn id(&self) -> &str {
        &self.target
    }

    fn platform(&self) -> DevicePlatform {
        DevicePlatform::Harmony
    }

    /// 异步执行 HDC Shell 指令
    async fn execute_shell(&self, cmd: &str) -> Result<String, String> {
        Self::run_hdc_cmd(
            &["-t", &self.target, "shell", cmd],
            Duration::from_secs(30),
        )
        .await
    }

    /// 异步抓取鸿蒙全屏截图并拉取至本地内存
    async fn take_screenshot(&self) -> Result<Vec<u8>, String> {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0);
        let pid = std::process::id();
        let remote_path = format!("/data/local/tmp/anydeck_screen_{timestamp}_{pid}.png");
        let local_path = std::env::temp_dir().join(format!("anydeck_screen_{timestamp}_{pid}.png"));
        let local_path_str = local_path.to_string_lossy().to_string();

        // 优先使用 uitest screenCap 截图，失败则回退到 snapshot_display
        let cap_res = self
            .execute_shell(&format!("uitest screenCap -p {remote_path}"))
            .await;
        if cap_res.is_err() {
            self.execute_shell(&format!("snapshot_display -f {remote_path}"))
                .await?;
        }

        // 拉取截图至本地临时文件
        let pull_res = self.pull_file(&remote_path, &local_path_str).await;

        // 异步尝试清理远程设备文件
        let target = self.target.clone();
        let remote_clean = remote_path.clone();
        tokio::spawn(async move {
            let _ = Self::run_hdc_cmd(
                &["-t", &target, "shell", &format!("rm {remote_clean}")],
                Duration::from_secs(5),
            )
            .await;
        });

        pull_res?;

        let bytes = tokio::fs::read(&local_path)
            .await
            .map_err(|e| format!("Failed to read screenshot file: {e}"))?;

        // 清理本地临时文件
        let _ = tokio::fs::remove_file(&local_path).await;

        if bytes.is_empty() {
            return Err("Empty screenshot returned from HarmonyOS device".into());
        }

        Ok(bytes)
    }

    /// 推送本地文件到鸿蒙远程设备
    async fn push_file(&self, local: &str, remote: &str) -> Result<(), String> {
        Self::run_hdc_cmd(
            &["-t", &self.target, "file", "send", local, remote],
            Duration::from_secs(300),
        )
        .await?;
        Ok(())
    }
}
