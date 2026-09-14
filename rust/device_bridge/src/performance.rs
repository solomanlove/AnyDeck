//! 零拷贝性能采样与增量计算引擎：直接通过 Direct ADB Socket 获取指标，
//! 在原生内存中原地切片解析 /proc/stat、meminfo、dumpsys 并计算 CPU / FPS 增量，
//! 向 Dart 交付定长 C-ABI 结构体。

use std::collections::HashMap;
use std::ffi::c_char;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use crate::adb_socket::AdbSocketClient;

/// 单个 CPU 核心的性能采样快照 (C-ABI 兼容)
#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct CoreUsageFFI {
    pub id: u32,
    pub usage: f32,       // 0.0 - 100.0
    pub freq_mhz: f32,    // 核心频率 (MHz)
}

/// 整机性能指标瞬时快照 (C-ABI 兼容，定长内存)
#[repr(C)]
pub struct PerformanceSnapshotFFI {
    pub overall_cpu: f32,
    pub total_mem_mb: f32,
    pub used_mem_mb: f32,
    pub mem_percent: f32,
    pub fps: f32,
    pub battery_level: i32,
    pub is_charging: bool,
    pub uptime_secs: u64,
    pub core_count: u32,
    pub cores: [CoreUsageFFI; 32],
    pub package_name: [c_char; 256],
}

impl Default for PerformanceSnapshotFFI {
    fn default() -> Self {
        Self {
            overall_cpu: 0.0,
            total_mem_mb: 0.0,
            used_mem_mb: 0.0,
            mem_percent: 0.0,
            fps: 0.0,
            battery_level: 100,
            is_charging: false,
            uptime_secs: 0,
            core_count: 0,
            cores: [CoreUsageFFI::default(); 32],
            package_name: [0; 256],
        }
    }
}

/// CPU 计数器（空闲时间片，总时间片）
#[derive(Clone, Copy, Default)]
struct CpuStat {
    idle: u64,
    total: u64,
}

/// 每个设备独立维护的历史上下文
struct DevicePerfContext {
    prev_cpu_stats: HashMap<String, CpuStat>,
    prev_total_frames: u64,
    prev_fps_time: Option<Instant>,
    last_fps: f32,
}

impl Default for DevicePerfContext {
    fn default() -> Self {
        Self {
            prev_cpu_stats: HashMap::new(),
            prev_total_frames: 0,
            prev_fps_time: None,
            last_fps: 0.0,
        }
    }
}

static PERF_CACHE: OnceLock<Mutex<HashMap<String, DevicePerfContext>>> = OnceLock::new();

fn perf_cache() -> &'static Mutex<HashMap<String, DevicePerfContext>> {
    PERF_CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

/// 清除指定设备的性能采样状态缓存（设备切换或断开时调用）
pub fn clear_device_cache(serial: &str) {
    if let Ok(mut cache) = perf_cache().lock() {
        cache.remove(serial);
    }
}

/// 聚合 ADB Shell 指令文本 (与原 Dart 保持一致，一次交互抓取全部指标)
pub const UNIFIED_SHELL_CMD: &str = r#"focusLine=$(dumpsys window | grep mCurrentFocus || true); cat /proc/uptime; echo "---"; dumpsys battery; echo "---"; cat /proc/meminfo; echo "---"; echo "$focusLine"; echo "---"; cat /proc/stat | grep "^cpu"; echo "---"; for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32; do if [ -d "/sys/devices/system/cpu/cpu$i" ]; then freq_file="/sys/devices/system/cpu/cpu$i/cpufreq/scaling_cur_freq"; if [ -f "$freq_file" ]; then cat "$freq_file"; else echo "0"; fi; fi; done; echo "---"; tmp=${focusLine%%/*}; pkg=${tmp##* }; pkg=${pkg##*{}; pkg=${pkg%%\}}; case "$pkg" in *.*) case "$pkg" in *[\{\}\/\=\ ]*) pkg="" ;; esac ;; *) pkg="" ;; esac; if [ -n "$pkg" ]; then dumpsys gfxinfo "$pkg" | grep "Total frames rendered:" || true; fi; true"#;

/// 轮询指定设备性能数据，计算增量后填充结构体
pub fn poll_device_performance(serial: &str, out: &mut PerformanceSnapshotFFI) -> Result<(), String> {
    // 1. 通过 Direct ADB Socket 执行命令，超时 2.5 秒
    let raw_bytes = AdbSocketClient::execute_shell(serial, UNIFIED_SHELL_CMD, Duration::from_millis(2500))?;
    let text = String::from_utf8_lossy(&raw_bytes);
    let now = Instant::now();

    let mut cache_guard = perf_cache()
        .lock()
        .map_err(|e| format!("Lock poisoned: {e}"))?;
    let ctx = cache_guard.entry(serial.to_string()).or_default();

    parse_performance_text(&text, ctx, out, now);
    Ok(())
}

/// 原地切片解析性能数据文本并计算增量
fn parse_performance_text(
    text: &str,
    ctx: &mut DevicePerfContext,
    out: &mut PerformanceSnapshotFFI,
    now: Instant,
) {
    let clean_text = text.replace("\r\n", "\n");
    let sections: Vec<&str> = clean_text.split("\n---\n").collect();

    // 3. Section 0: Uptime
    if let Some(sec0) = sections.first() {
        if let Some(first_word) = sec0.split_whitespace().next() {
            if let Ok(secs) = first_word.parse::<f64>() {
                out.uptime_secs = secs as u64;
            }
        }
    }

    // 4. Section 1: Battery
    if sections.len() > 1 {
        for line in sections[1].lines() {
            let trimmed = line.trim();
            if let Some(val) = trimmed.strip_prefix("level:") {
                if let Ok(lvl) = val.trim().parse::<i32>() {
                    out.battery_level = lvl;
                }
            } else if let Some(val) = trimmed.strip_prefix("status:") {
                if let Ok(status) = val.trim().parse::<i32>() {
                    out.is_charging = status == 2 || status == 5;
                }
            } else if trimmed.contains("powered: true") {
                out.is_charging = true;
            }
        }
    }

    // 5. Section 2: Meminfo
    if sections.len() > 2 {
        let mut total_kb = 0.0;
        let mut avail_kb = 0.0;
        let mut free_kb = 0.0;
        let mut cached_kb = 0.0;
        let mut buffers_kb = 0.0;

        for line in sections[2].lines() {
            let trimmed = line.trim();
            if let Some(val) = trimmed.strip_prefix("MemTotal:") {
                total_kb = parse_first_number(val);
            } else if let Some(val) = trimmed.strip_prefix("MemAvailable:") {
                avail_kb = parse_first_number(val);
            } else if let Some(val) = trimmed.strip_prefix("MemFree:") {
                free_kb = parse_first_number(val);
            } else if let Some(val) = trimmed.strip_prefix("Cached:") {
                cached_kb = parse_first_number(val);
            } else if let Some(val) = trimmed.strip_prefix("Buffers:") {
                buffers_kb = parse_first_number(val);
            }
        }

        if avail_kb <= 0.0 {
            avail_kb = free_kb + cached_kb + buffers_kb;
        }

        out.total_mem_mb = (total_kb / 1024.0) as f32;
        let used_kb = if total_kb > avail_kb { total_kb - avail_kb } else { 0.0 };
        out.used_mem_mb = (used_kb / 1024.0) as f32;
        out.mem_percent = if out.total_mem_mb > 0.0 {
            (out.used_mem_mb / out.total_mem_mb * 100.0).clamp(0.0, 100.0)
        } else {
            0.0
        };
    }

    // 6. Section 3: Foreground Package
    if sections.len() > 3 {
        let focus_line = sections[3].trim();
        if !focus_line.is_empty() && !focus_line.contains("mCurrentFocus=null") {
            if let Some(first_part) = focus_line.split('/').next() {
                if let Some(token) = first_part.split_whitespace().last() {
                    let mut clean_pkg = token;
                    if let Some(idx) = clean_pkg.find('{') {
                        clean_pkg = &clean_pkg[idx + 1..];
                    }
                    if let Some(idx) = clean_pkg.find('}') {
                        clean_pkg = &clean_pkg[..idx];
                    }
                    if !clean_pkg.contains('=') {
                        write_package_name(clean_pkg, &mut out.package_name);
                    }
                }
            }
        }
    }

    // 7. Section 5: CPU Frequencies (提前解析以便填充 cores)
    let mut freqs_mhz = Vec::new();
    if sections.len() > 5 {
        for line in sections[5].lines() {
            let trimmed = line.trim();
            if let Ok(khz) = trimmed.parse::<f32>() {
                freqs_mhz.push(khz / 1000.0);
            }
        }
    }

    // 8. Section 4: CPU /proc/stat 差值计算
    if sections.len() > 4 {
        let mut new_stats = HashMap::new();
        let mut core_list = Vec::new();

        for line in sections[4].lines() {
            let trimmed = line.trim();
            if !trimmed.starts_with("cpu") {
                continue;
            }
            let parts: Vec<&str> = trimmed.split_whitespace().collect();
            if parts.len() < 5 {
                continue;
            }

            let key = parts[0].to_string();
            let user = parts[1].parse::<u64>().unwrap_or(0);
            let nice = parts[2].parse::<u64>().unwrap_or(0);
            let system = parts[3].parse::<u64>().unwrap_or(0);
            let idle_time = parts[4].parse::<u64>().unwrap_or(0);
            let iowait = parts.get(5).and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
            let irq = parts.get(6).and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
            let softirq = parts.get(7).and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
            let steal = parts.get(8).and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);

            let idle = idle_time + iowait;
            let non_idle = user + nice + system + irq + softirq + steal;
            let total = idle + non_idle;
            let current_stat = CpuStat { idle, total };
            new_stats.insert(key.clone(), current_stat);

            // 计算增量使用率
            let mut usage = 0.0f32;
            if let Some(prev) = ctx.prev_cpu_stats.get(&key) {
                let total_delta = total.saturating_sub(prev.total);
                let idle_delta = idle.saturating_sub(prev.idle);
                if total_delta > 0 {
                    usage = ((total_delta.saturating_sub(idle_delta)) as f32 / total_delta as f32 * 100.0)
                        .clamp(0.0, 100.0);
                }
            }

            if key == "cpu" {
                out.overall_cpu = usage;
            } else if let Ok(core_id) = key.trim_start_matches("cpu").parse::<u32>() {
                let freq = freqs_mhz.get(core_id as usize).copied().unwrap_or(0.0);
                core_list.push(CoreUsageFFI {
                    id: core_id,
                    usage,
                    freq_mhz: freq,
                });
            }
        }

        ctx.prev_cpu_stats.extend(new_stats);

        // 排序并存入 out.cores
        core_list.sort_by_key(|c| c.id);
        out.core_count = core_list.len().min(32) as u32;
        for (i, core) in core_list.into_iter().take(32).enumerate() {
            out.cores[i] = core;
        }
    }

    // 9. Section 6: Gfxinfo (实时渲染 FPS 计算)
    if sections.len() > 6 {
        let mut total_frames = 0u64;
        let gfx_line = sections[6].trim();
        if let Some(idx) = gfx_line.find("Total frames rendered:") {
            let sub = &gfx_line[idx + "Total frames rendered:".len()..];
            if let Some(first_word) = sub.split_whitespace().next() {
                if let Ok(frames) = first_word.parse::<u64>() {
                    total_frames = frames;
                }
            }
        }

        if total_frames > 0 && ctx.prev_total_frames > 0 {
            if let Some(prev_time) = ctx.prev_fps_time {
                let delta_frames = total_frames.saturating_sub(ctx.prev_total_frames);
                let elapsed_secs = now.duration_since(prev_time).as_secs_f32();
                if elapsed_secs > 0.0 && delta_frames > 0 {
                    out.fps = (delta_frames as f32 / elapsed_secs).clamp(0.0, 120.0);
                } else {
                    out.fps = 0.0;
                }
            }
        } else {
            out.fps = 0.0;
        }

        ctx.prev_total_frames = total_frames;
        ctx.prev_fps_time = Some(now);
        ctx.last_fps = out.fps;
    }
}

fn parse_first_number(s: &str) -> f64 {
    for token in s.split_whitespace() {
        if let Ok(num) = token.parse::<f64>() {
            return num;
        }
    }
    0.0
}

fn write_package_name(src: &str, dst: &mut [c_char; 256]) {
    let bytes = src.as_bytes();
    let len = bytes.len().min(255);
    for i in 0..len {
        dst[i] = bytes[i] as c_char;
    }
    dst[len] = 0;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_performance_text() {
        let mock_output = "12345.67 23456.78\n---\nlevel: 85\nstatus: 2\npowered: true\n---\nMemTotal:        8000000 kB\nMemAvailable:    3000000 kB\nMemFree:         1000000 kB\nCached:          1500000 kB\nBuffers:          500000 kB\n---\nmCurrentFocus=Window{123 u0 com.example.testapp/com.example.testapp.MainActivity}\n---\ncpu  1000 0 1000 8000 0 0 0 0 0 0\ncpu0 500 0 500 4000 0 0 0 0 0 0\ncpu1 500 0 500 4000 0 0 0 0 0 0\n---\n1800000\n1800000\n---\nTotal frames rendered: 100\n";
        let mut ctx = DevicePerfContext::default();
        let mut out = PerformanceSnapshotFFI::default();
        let now = Instant::now();

        parse_performance_text(mock_output, &mut ctx, &mut out, now);

        assert_eq!(out.uptime_secs, 12345);
        assert_eq!(out.battery_level, 85);
        assert!(out.is_charging);
        assert!((out.total_mem_mb - (8000000.0 / 1024.0)).abs() < 0.1);
        assert!((out.used_mem_mb - (5000000.0 / 1024.0)).abs() < 0.1);

        // 验证第二次采样（差值计算）
        let mock_output_2 = "12346.67 23457.78\n---\nlevel: 85\nstatus: 2\npowered: true\n---\nMemTotal:        8000000 kB\nMemAvailable:    3000000 kB\n---\nmCurrentFocus=Window{123 u0 com.example.testapp/com.example.testapp.MainActivity}\n---\ncpu  1100 0 1100 8800 0 0 0 0 0 0\ncpu0 550 0 550 4400 0 0 0 0 0 0\ncpu1 550 0 550 4400 0 0 0 0 0 0\n---\n1800000\n1800000\n---\nTotal frames rendered: 160\n";
        let now2 = now + Duration::from_secs(1);
        parse_performance_text(mock_output_2, &mut ctx, &mut out, now2);

        // 总体 CPU delta: total = 1000, idle = 800 -> usage = (1000-800)/1000 = 20%
        assert!((out.overall_cpu - 20.0).abs() < 0.5);
        assert_eq!(out.core_count, 2);
        assert!((out.cores[0].usage - 20.0).abs() < 0.5);
        assert!((out.cores[0].freq_mhz - 1800.0).abs() < 0.1);
        // FPS delta: (160 - 100) / 1.0s = 60 FPS
        assert!((out.fps - 60.0).abs() < 1.0);
    }
}

