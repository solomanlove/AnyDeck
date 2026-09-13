//! ADB 命令、server 子进程和端口由 Rust 管理；Drop 确保异常路径回收。
use std::io::Read;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

pub fn command(executable: &str, args: &[&str], stopped: &AtomicBool) -> Result<String, String> {
    let mut child = Command::new(executable)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| e.to_string())?;
    let mut stdout = child.stdout.take().ok_or("Missing ADB stdout")?;
    // 排空所有输出，仅保留 4096 字节；不会因 pipe 写满而阻塞子进程。
    let reader = std::thread::spawn(move || {
        let mut result = Vec::new();
        let mut bytes = [0; 1024];
        while let Ok(count) = stdout.read(&mut bytes) {
            if count == 0 {
                break;
            }
            let keep = count.min(4096 - result.len());
            result.extend_from_slice(&bytes[..keep]);
        }
        String::from_utf8_lossy(&result).into_owned()
    });
    let deadline = Instant::now() + Duration::from_secs(15);
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break Ok(status),
            Ok(None) => {}
            Err(error) => break Err(error.to_string()),
        }
        if stopped.load(Ordering::Acquire) || Instant::now() > deadline {
            break Err("ADB cancelled or timed out".into());
        }
        std::thread::sleep(Duration::from_millis(20));
    };
    if status.is_err() {
        let _ = child.kill();
        let _ = child.wait();
    }
    let output = reader.join().map_err(|_| "ADB output worker failed")?;
    if !status?.success() {
        return Err("ADB command failed".into());
    }
    Ok(output)
}

pub struct Transport {
    adb: String,
    serial: String,
    remote_jar: String,
    socket_name: String,
    forwarding: bool,
    pub port: u16,
    child: Option<Child>,
}
impl Transport {
    pub fn start(
        adb: String,
        serial: String,
        jar: String,
        kind: u8,
        token: u64,
        stopped: &AtomicBool,
    ) -> Result<Self, String> {
        let sdk = command(
            &adb,
            &["-s", &serial, "shell", "getprop", "ro.build.version.sdk"],
            stopped,
        )?
        .trim()
        .parse::<u32>()
        .map_err(|_| "Unknown Android SDK")?;
        if sdk
            < match kind {
                0 | 3 => 31,
                1 => 30,
                _ => 21,
            }
        {
            return Err("Unsupported Android version".into());
        }
        let scid = format!("{:x}", token & 0x7fffffff);
        let socket = format!("localabstract:scrcpy_{:08x}", token & 0x7fffffff);
        let mut transport = Self {
            adb,
            serial,
            remote_jar: format!("/data/local/tmp/anydeck-{scid}.jar"),
            socket_name: socket.clone(),
            forwarding: false,
            port: 0,
            child: None,
        };
        command(
            &transport.adb,
            &["-s", &transport.serial, "push", &jar, &transport.remote_jar],
            stopped,
        )?;
        transport.forwarding = true;
        // 让原子端口分配完整返回，再检查取消，避免端口已建立但尚未记录。
        transport.port = command(
            &transport.adb,
            &["-s", &transport.serial, "forward", "tcp:0", &socket],
            &AtomicBool::new(false),
        )?
        .trim()
        .parse()
        .map_err(|_| "Invalid ADB forward port")?;
        if stopped.load(Ordering::Acquire) {
            return Err("Cancelled".into());
        }
        let classpath = format!("CLASSPATH={}", transport.remote_jar);
        let scid_arg = format!("scid={scid}");
        let mut args = vec![
            "-s",
            &transport.serial,
            "shell",
            &classpath,
            "app_process",
            "/",
            "com.genymobile.scrcpy.Server",
            "4.0",
            &scid_arg,
            "log_level=warn",
            "tunnel_forward=true",
            "send_device_meta=false",
            "send_dummy_byte=true",
            "power_on=false",
        ];
        if kind == 0 || kind == 3 {
            args.extend([
                "video=true",
                "audio=false",
                "control=false",
                "video_source=camera",
                "video_codec=h264",
                "camera_fps=30",
                "max_size=1280",
                "video_bit_rate=4000000",
                "clipboard_autosync=false",
                if kind == 3 {
                    "camera_facing=front"
                } else {
                    "camera_facing=back"
                },
            ]);
        } else if kind == 1 {
            args.extend([
                "video=false",
                "audio=true",
                "control=false",
                "audio_source=mic",
                "audio_codec=raw",
                "send_frame_meta=false",
            ]);
        } else {
            args.extend([
                "video=false",
                "audio=false",
                "control=true",
                "clipboard_autosync=true",
            ]);
        }
        transport.child = Some(
            Command::new(&transport.adb)
                .args(args)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
                .map_err(|e| e.to_string())?,
        );
        Ok(transport)
    }
    pub fn alive(&mut self) -> bool {
        self.child
            .as_mut()
            .and_then(|child| child.try_wait().ok())
            .flatten()
            .is_none()
    }
}
impl Drop for Transport {
    fn drop(&mut self) {
        if let Some(child) = self.child.as_mut() {
            let _ = child.kill();
            let _ = child.wait();
        }
        let stopped = AtomicBool::new(false);
        if self.port == 0 && self.forwarding {
            // 超时可能发生在 ADB 已建立映射之后，只按本次唯一 socket 定位清理。
            if let Ok(list) = command(&self.adb, &["forward", "--list"], &stopped) {
                for line in list.lines() {
                    let fields: Vec<_> = line.split_whitespace().collect();
                    if fields.len() == 3
                        && fields[0] == self.serial
                        && fields[2] == self.socket_name
                    {
                        self.port = fields[1]
                            .strip_prefix("tcp:")
                            .and_then(|port| port.parse().ok())
                            .unwrap_or(0);
                        break;
                    }
                }
            }
        }
        if self.port != 0 {
            let _ = command(
                &self.adb,
                &[
                    "-s",
                    &self.serial,
                    "forward",
                    "--remove",
                    &format!("tcp:{}", self.port),
                ],
                &stopped,
            );
        }
        let _ = command(
            &self.adb,
            &["-s", &self.serial, "shell", "rm", "-f", &self.remote_jar],
            &stopped,
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    #[test]
    fn cancellation_kills_child() {
        let stopped = Arc::new(AtomicBool::new(false));
        let signal = stopped.clone();
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(60));
            signal.store(true, Ordering::Release);
        });
        let start = Instant::now();
        assert!(command("/bin/sleep", &["10"], &stopped).is_err());
        assert!(start.elapsed() < Duration::from_secs(2));
    }
    #[test]
    fn bounded_output() {
        assert_eq!(
            command(
                "/usr/bin/printf",
                &["%05000d", "1"],
                &AtomicBool::new(false)
            )
            .unwrap()
            .len(),
            4096
        );
    }
}
