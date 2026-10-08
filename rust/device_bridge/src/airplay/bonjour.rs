//! macOS 原生 Bonjour (mDNS) 服务广播，基于 libSystem 中的 dns_sd API。
//! 服务发现仅表示可见，不代表已具备完整媒体接收能力。

use std::ffi::{c_char, c_void, CString};
use std::ptr;

/// legacy 镜像协商能力；不宣称音频、云播放或 HomeKit 配对。
pub const AIRPLAY_FEATURES: u64 = (1 << 7) | (1 << 8) | (1 << 12) | (1 << 14) | (1 << 27);
pub const AIRPLAY_STATUS_FLAGS: u64 = 4;

/// /info 与 DNS-SD 使用同一份 64 位能力位，避免协商路径不一致。
fn features_txt() -> String {
    format!("0x{:X},0x{:X}", AIRPLAY_FEATURES as u32, AIRPLAY_FEATURES >> 32)
}

type DNSServiceRef = *mut c_void;
type DNSServiceErrorType = i32;

#[link(name = "System")]
extern "C" {
    fn DNSServiceRegister(
        sd_ref: *mut DNSServiceRef,
        flags: u32,
        interface_index: u32,
        name: *const c_char,
        regtype: *const c_char,
        domain: *const c_char,
        host: *const c_char,
        port: u16,
        txt_len: u16,
        txt_record: *const c_void,
        callback: *const c_void,
        context: *mut c_void,
    ) -> DNSServiceErrorType;

    fn DNSServiceRefDeallocate(sd_ref: DNSServiceRef);
}

/// DNS-SD TXT 记录编码辅助类：[长度 (1字节), 内容 ("key=value")...]
#[derive(Default)]
pub struct TxtRecord {
    bytes: Vec<u8>,
}

impl TxtRecord {
    pub fn new() -> Self {
        Self::default()
    }

    /// 写入一条属性对 (key=value)
    pub fn set(&mut self, key: &str, value: &str) {
        let entry = format!("{key}={value}");
        let len = entry.len();
        if len > 255 {
            return;
        }
        self.bytes.push(len as u8);
        self.bytes.extend_from_slice(entry.as_bytes());
    }

    pub fn as_bytes(&self) -> &[u8] {
        &self.bytes
    }
}

/// 承载单个 Bonjour 服务注册句柄，Drop 时自动注销广播。
pub struct BonjourRegistration {
    sd_ref: DNSServiceRef,
}

unsafe impl Send for BonjourRegistration {}
unsafe impl Sync for BonjourRegistration {}

impl BonjourRegistration {
    /// 注册一个服务
    /// - `name`: 显示名称（若为 None 则使用系统默认设备名）
    /// - `regtype`: 如 "_airplay._tcp" 或 "_raop._tcp"
    /// - `port`: 本机监听端口（主机字节序，内部自动转换为网络字节序）
    /// - `txt`: 可选的 TXT Record
    pub fn register(
        name: Option<&str>,
        regtype: &str,
        port: u16,
        txt: Option<&TxtRecord>,
    ) -> Result<Self, String> {
        let mut sd_ref: DNSServiceRef = ptr::null_mut();

        let c_name = match name {
            Some(n) => Some(CString::new(n).map_err(|e| e.to_string())?),
            None => None,
        };
        let c_regtype = CString::new(regtype).map_err(|e| e.to_string())?;

        let (txt_len, txt_ptr) = match txt {
            Some(t) => (t.as_bytes().len() as u16, t.as_bytes().as_ptr() as *const c_void),
            None => (0, ptr::null()),
        };

        let err = unsafe {
            DNSServiceRegister(
                &mut sd_ref,
                0, // 默认 flags
                0, // 所有接口 (0 表示 kDNSServiceInterfaceIndexAny)
                c_name.as_ref().map_or(ptr::null(), |n| n.as_ptr()),
                c_regtype.as_ptr(),
                ptr::null(), // 默认 domain (.local)
                ptr::null(), // 默认 host
                port.to_be(), // 转为网络大端序
                txt_len,
                txt_ptr,
                ptr::null(), // 同步/异步无回调句柄
                ptr::null_mut(),
            )
        };

        if err != 0 || sd_ref.is_null() {
            return Err(format!("DNSServiceRegister failed for {regtype} with code: {err}"));
        }

        Ok(Self { sd_ref })
    }
}

impl Drop for BonjourRegistration {
    fn drop(&mut self) {
        if !self.sd_ref.is_null() {
            unsafe {
                DNSServiceRefDeallocate(self.sd_ref);
            }
            self.sd_ref = ptr::null_mut();
        }
    }
}

/// AirPlay 服务广播组合器：同时广播 `_airplay._tcp` 与 `_raop._tcp`
pub struct AirPlayAdvertiser {
    _airplay: BonjourRegistration,
    _raop: Option<BonjourRegistration>,
}

impl AirPlayAdvertiser {
    /// 构造 _airplay._tcp TXT 记录
    pub fn build_airplay_txt(mac_addr: &str, pk_hex: &str) -> TxtRecord {
        let mut airplay_txt = TxtRecord::new();
        airplay_txt.set("acl", "0");
        airplay_txt.set("deviceid", mac_addr);
        airplay_txt.set("features", &features_txt());
        airplay_txt.set("flags", &format!("0x{AIRPLAY_STATUS_FLAGS:X}"));
        airplay_txt.set("model", "AppleTV3,2");
        airplay_txt.set("srcvers", "220.68");
        airplay_txt.set("pi", "3e75fac4-1b89-4572-a5ee-4dd121c46872");
        airplay_txt.set("pk", pk_hex);
        airplay_txt.set("vv", "2");
        airplay_txt
    }

    /// 构造 _raop._tcp TXT 记录
    pub fn build_raop_txt(pk_hex: &str) -> TxtRecord {
        let mut raop_txt = TxtRecord::new();
        raop_txt.set("ch", "2");
        raop_txt.set("cn", "0,1,2,3");
        raop_txt.set("da", "true");
        raop_txt.set("et", "0,3,5");
        raop_txt.set("ft", &features_txt());
        raop_txt.set("sf", &format!("0x{AIRPLAY_STATUS_FLAGS:X}"));
        raop_txt.set("md", "0,1,2");
        raop_txt.set("am", "AppleTV3,2");
        raop_txt.set("pk", pk_hex);
        raop_txt.set("tp", "UDP");
        raop_txt.set("vn", "65537");
        raop_txt.set("vs", "220.68");
        raop_txt.set("vv", "2");
        raop_txt
    }

    /// 启动 AirPlay 屏幕镜像广播
    /// - `name`: 电脑在 iPhone 屏幕镜像列表中显示的名称 (如 "AnyDeck-Mac")
    /// - `mac_addr`: 格式如 "48:A9:D2:01:02:03"
    /// - `port`: RTSP 监听端口 (一般 7000)
    /// - `pk_hex`: Ed25519 公钥十六进制字符串
    pub fn start(name: &str, mac_addr: &str, port: u16, pk_hex: &str) -> Result<Self, String> {
        // 1. 构造 _airplay._tcp TXT 记录（模拟兼容性最佳的 AppleTV3,2 标准镜像规格）
        let airplay_txt = Self::build_airplay_txt(mac_addr, pk_hex);

        let airplay_reg = BonjourRegistration::register(
            Some(name),
            "_airplay._tcp",
            port,
            Some(&airplay_txt),
        )?;

        // 2. 构造 _raop._tcp 记录
        let mac_clean = mac_addr.replace(':', "").to_uppercase();
        let raop_name = format!("{mac_clean}@{name}");
        let raop_txt = Self::build_raop_txt(pk_hex);

        let raop_reg = BonjourRegistration::register(
            Some(&raop_name),
            "_raop._tcp",
            port,
            Some(&raop_txt),
        ).ok();

        Ok(Self {
            _airplay: airplay_reg,
            _raop: raop_reg,
        })
    }
}
