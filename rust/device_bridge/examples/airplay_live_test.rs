//! AirPlay 投屏真机实时监听测试程序
use std::ffi::CString;
use std::thread::sleep;
use std::time::Duration;

use anydeck_device_bridge::c_api_airplay::*;

fn main() {
    println!("==================================================");
    println!(">>> 正在启动 AnyDeck AirPlay Server 屏幕镜像广播...");
    println!("==================================================");

    // 可使用独立名称和端口，与正在运行的桌面 App 区分。
    let args: Vec<String> = std::env::args().collect();
    let service_name = args.get(1).map(String::as_str).unwrap_or("AnyDeck-AirPlay-Test");
    let seconds: u64 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(300);
    let name = CString::new(service_name).unwrap();
    let id = unsafe { anydeck_airplay_start(name.as_ptr(), 7030, 7130) };

    if id == 0 {
        eprintln!("[ERROR] 启动 AirPlay Server 失败！");
        return;
    }

    println!("[SUCCESS] AirPlay 服务已启动！会话 ID = {id}");
    println!("请在 iPhone 手机上：");
    println!("  1. 下拉控制中心；");
    println!("  2. 点击【屏幕镜像】(两个矩形图标)；");
    println!("  3. 选择列表中出现的【{service_name}】进行无线投屏！");
    println!("正在监听 iPhone 连接请求 (持续监听 {seconds} 秒)...");

    let mut connected = false;
    for i in 1..=seconds.saturating_mul(2) {
        sleep(Duration::from_millis(500));
        let status = anydeck_airplay_get_status(id);
        let mut w = 0u32;
        let mut h = 0u32;
        let has_dim = unsafe { anydeck_airplay_get_dimensions(id, &mut w, &mut h) };
        let has_surface = anydeck_airplay_has_surface(id);

        if status == 1 {
            if !connected {
                println!("\n>>> [CONNECTED!] 收到 iPhone 投屏连接！");
                connected = true;
            }
            if has_dim && w > 0 {
                println!("[STREAM] 视频流正常解码中: 分辨率 = {w}x{h}, IOSurface 就绪 = {has_surface}");
            }
        } else if i % 10 == 0 {
            connected = false;
            println!("... 等待连接中 (Status = {status}, elapsed = {}s) ...", i / 2);
        }
    }

    println!("\n>>> 测试结束，正在安全关闭 AirPlay 服务...");
    anydeck_airplay_stop(id);
    println!("[SUCCESS] AirPlay 服务已关闭。");
}
