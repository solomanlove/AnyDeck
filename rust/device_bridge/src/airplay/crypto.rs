//! AirPlay legacy 配对验证：X25519 + Ed25519 + AES-128-CTR。
//! 配对密钥仅用于认证，不能代替 FairPlay 解包后的媒体密钥。

use aes::cipher::{KeyIvInit, StreamCipher};
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use rand::rngs::OsRng;
use sha2::{Digest, Sha512};
use x25519_dalek::{EphemeralSecret, PublicKey};

type Aes128Ctr = ctr::Ctr128BE<aes::Aes128>;

// 暂时保留已有服务身份；持久化每安装实例密钥需在正式发布前单独完善。
pub const AIRPLAY_ED25519_SEED: [u8; 32] = [
    0x38, 0x4a, 0x1d, 0x9f, 0x77, 0x22, 0x8a, 0x4b,
    0xc1, 0x90, 0x33, 0xee, 0x5d, 0xaa, 0x61, 0x09,
    0x7b, 0x55, 0x12, 0x44, 0x9f, 0x88, 0x01, 0x3e,
    0xa4, 0x67, 0x29, 0x10, 0x5c, 0xd0, 0xee, 0x82,
];

/// 待验证上下文仅属于当前 RTSP 连接，不能在客户端之间共享。
struct PendingVerify {
    cipher: Aes128Ctr,
    client_identity: VerifyingKey,
    client_public: [u8; 32],
    server_public: [u8; 32],
}

/// 管理 legacy 配对两阶段状态，失败时销毁待验证上下文。
pub struct AirPlayCrypto {
    signing_key: SigningKey,
    pending: Option<PendingVerify>,
    verified: bool,
}

impl Default for AirPlayCrypto {
    fn default() -> Self { Self::new() }
}

impl AirPlayCrypto {
    pub fn new() -> Self {
        Self {
            signing_key: SigningKey::from_bytes(&AIRPLAY_ED25519_SEED),
            pending: None,
            verified: false,
        }
    }

    pub fn public_key_bytes(&self) -> [u8; 32] {
        *self.signing_key.verifying_key().as_bytes()
    }

    pub fn public_key_hex(&self) -> String {
        self.public_key_bytes().iter().map(|b| format!("{b:02x}")).collect()
    }

    pub fn is_verified(&self) -> bool { self.verified }

    /// 请求必须为 flag + X25519 公钥 + Ed25519 公钥，共 68 字节。
    /// 响应为 32 字节服务端公钥和 64 字节 CTR 密文，没有 AEAD tag。
    pub fn handle_pair_verify_1(&mut self, data: &[u8]) -> Result<Vec<u8>, String> {
        self.pending = None;
        self.verified = false;
        if data.len() != 68 || data[..4] != [1, 0, 0, 0] {
            return Err("Invalid legacy pair-verify stage 1 (expected 68 bytes, flag 1)".into());
        }
        let client_public: [u8; 32] = data[4..36].try_into().unwrap();
        let identity: [u8; 32] = data[36..68].try_into().unwrap();
        let client_identity = VerifyingKey::from_bytes(&identity)
            .map_err(|_| "Invalid client Ed25519 public key")?;
        if client_identity.is_weak() {
            return Err("Weak client Ed25519 public key".into());
        }
        let secret = EphemeralSecret::random_from_rng(OsRng);
        let server_public = PublicKey::from(&secret).to_bytes();
        let shared = secret.diffie_hellman(&PublicKey::from(client_public));
        if !shared.was_contributory() {
            return Err("Invalid client X25519 public key".into());
        }
        let derive = |label: &[u8]| -> [u8; 16] {
            let mut hash = Sha512::new();
            hash.update(label);
            hash.update(shared.as_bytes());
            hash.finalize()[..16].try_into().unwrap()
        };
        let key = derive(b"Pair-Verify-AES-Key");
        let iv = derive(b"Pair-Verify-AES-IV");
        let mut cipher = Aes128Ctr::new(&key.into(), &iv.into());
        let message = [server_public, client_public].concat();
        let mut signature = self.signing_key.sign(&message).to_bytes();
        cipher.apply_keystream(&mut signature);
        // 第二阶段从同一 CTR 流的第 64 字节继续，不能重新初始化 IV。
        self.pending = Some(PendingVerify {
            cipher, client_identity, client_public, server_public,
        });
        Ok([server_public.as_slice(), signature.as_slice()].concat())
    }

    /// 校验客户端证明；拒绝空包、重放、损坏签名以及未完成第一阶段的请求。
    pub fn handle_pair_verify_2(&mut self, data: &[u8]) -> Result<(), String> {
        self.verified = false;
        let mut pending = self.pending.take().ok_or("pair-verify stage 1 required")?;
        if data.len() != 68 || data[..4] != [0, 0, 0, 0] {
            return Err("Invalid legacy pair-verify stage 2 (expected 68 bytes, flag 0)".into());
        }
        let mut signature: [u8; 64] = data[4..].try_into().unwrap();
        pending.cipher.apply_keystream(&mut signature);
        let message = [pending.client_public, pending.server_public].concat();
        pending.client_identity.verify_strict(&message, &Signature::from_bytes(&signature))
            .map_err(|_| "pair-verify client signature rejected")?;
        self.verified = true;
        Ok(())
    }
}
