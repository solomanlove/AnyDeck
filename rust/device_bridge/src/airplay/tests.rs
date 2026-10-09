//! 独立 legacy 客户端与线格式回归，不把模拟成功等同于真机出画。
use super::*;
use aes::cipher::{KeyIvInit, StreamCipher};
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use sha2::{Digest, Sha512};
use x25519_dalek::{PublicKey, StaticSecret};
use rtsp::RtspRequest;

type Ctr = ctr::Ctr128BE<aes::Aes128>;

fn session() -> RtspSession {
    let crypto = AirPlayCrypto::new();
    RtspSession::new("Test", "02:00:00:00:00:01", 7100,
        AirPlayAdvertiser::build_airplay_txt("02:00:00:00:00:01", &crypto.public_key_hex()).as_bytes().to_vec())
}

fn request(method: &str, uri: &str, body: Vec<u8>) -> RtspRequest {
    RtspRequest { method: method.into(), uri: uri.into(), body, ..Default::default() }
}

fn body(response: &[u8]) -> &[u8] {
    let pos = response.windows(4).position(|bytes| bytes == b"\r\n\r\n").unwrap();
    &response[pos + 4..]
}

/// 独立构造客户端密钥和报文，不调用服务端派生函数。
pub(super) struct Client {
    secret: StaticSecret,
    identity: SigningKey,
}

impl Client {
    pub(super) fn new(seed: u8) -> Self {
        Self { secret: StaticSecret::from([seed; 32]), identity: SigningKey::from_bytes(&[seed + 1; 32]) }
    }
    pub(super) fn first(&self) -> Vec<u8> {
        [[1,0,0,0].as_slice(), PublicKey::from(&self.secret).as_bytes(),
            self.identity.verifying_key().as_bytes()].concat()
    }
    pub(super) fn second(&self, response: &[u8], server_identity: [u8; 32], tamper: bool) -> Vec<u8> {
        assert_eq!(response.len(), 96, "legacy 不包含 ChaCha20 AEAD tag");
        let remote = PublicKey::from(<[u8;32]>::try_from(&response[..32]).unwrap());
        let shared = self.secret.diffie_hellman(&remote);
        let key = Sha512::digest([b"Pair-Verify-AES-Key".as_slice(), shared.as_bytes()].concat());
        let iv = Sha512::digest([b"Pair-Verify-AES-IV".as_slice(), shared.as_bytes()].concat());
        let mut ctr = Ctr::new_from_slices(&key[..16], &iv[..16]).unwrap();
        let mut proof = response[32..].to_vec();
        ctr.apply_keystream(&mut proof);
        let public = PublicKey::from(&self.secret);
        VerifyingKey::from_bytes(&server_identity).unwrap().verify_strict(
            &[remote.as_bytes().as_slice(), public.as_bytes()].concat(),
            &Signature::from_slice(&proof).unwrap()).unwrap();
        let mut proof = self.identity.sign(&[public.as_bytes().as_slice(), remote.as_bytes()].concat()).to_bytes();
        ctr.apply_keystream(&mut proof);
        if tamper { proof[0] ^= 1; }
        [[0,0,0,0].as_slice(), &proof].concat()
    }
}

#[test]
fn legacy_pairing_roundtrip_and_stage_two_dispatch() {
    let mut server = session();
    let client = Client::new(10);
    let setup = server.handle_request(&request("POST", "/pair-setup", client.identity.verifying_key().to_bytes().to_vec())).unwrap();
    assert_eq!(body(&setup), server.crypto.public_key_bytes());
    let first = server.handle_request(&request("POST", "/pair-verify", client.first())).unwrap();
    let second = client.second(body(&first), server.crypto.public_key_bytes(), false);
    assert_eq!(second.len(), 68);
    let response = server.handle_request(&request("POST", "/pair-verify", second.clone())).unwrap();
    assert!(response.starts_with(b"RTSP/1.0 200"));
    assert!(body(&response).is_empty());
    assert!(server.crypto.is_verified());
    let replay = server.handle_request(&request("POST", "/pair-verify", second)).unwrap();
    assert!(replay.starts_with(b"RTSP/1.0 403"));
}

#[test]
fn rejects_bad_proofs_and_missing_stage_one() {
    let mut crypto = AirPlayCrypto::new();
    assert!(crypto.handle_pair_verify_2(&[0;68]).is_err());
    assert!(crypto.handle_pair_verify_1(&[1;36]).is_err());
    let client = Client::new(20);
    let first = crypto.handle_pair_verify_1(&client.first()).unwrap();
    let bad = client.second(&first, crypto.public_key_bytes(), true);
    assert!(crypto.handle_pair_verify_2(&bad).is_err());
    assert!(!crypto.is_verified());
    assert!(crypto.handle_pair_verify_2(&[]).is_err());
    let mut zero_ecdh = client.first();
    zero_ecdh[4..36].fill(0);
    assert!(crypto.handle_pair_verify_1(&zero_ecdh).is_err());
}

#[test]
fn clients_cannot_overwrite_each_others_pairing() {
    let (mut a, mut b) = (session(), session());
    let (ca, cb) = (Client::new(30), Client::new(40));
    let ra = a.crypto.handle_pair_verify_1(&ca.first()).unwrap();
    let rb = b.crypto.handle_pair_verify_1(&cb.first()).unwrap();
    a.crypto.handle_pair_verify_2(&ca.second(&ra, a.crypto.public_key_bytes(), false)).unwrap();
    b.crypto.handle_pair_verify_2(&cb.second(&rb, b.crypto.public_key_bytes(), false)).unwrap();
}

#[test]
fn qualified_info_preserves_identity_and_matches_bonjour() {
    let mut server = session();
    let mut qualifier = plist::Dictionary::new();
    qualifier.insert("qualifier".into(), plist::Value::Array(vec!["txtAirPlay".into()]));
    let mut encoded = Vec::new();
    plist::Value::Dictionary(qualifier).to_writer_binary(&mut encoded).unwrap();
    let mut req = request("GET", "/info", encoded);
    req.headers.insert("content-type".into(), "application/x-apple-binary-plist".into());
    let response = server.handle_request(&req).unwrap();
    let value = plist::Value::from_reader(std::io::Cursor::new(body(&response))).unwrap();
    let dict = value.as_dictionary().unwrap();
    assert_eq!(dict["pk"].as_data().unwrap(), server.crypto.public_key_bytes());
    assert_eq!(dict["features"].as_unsigned_integer(), Some(bonjour::AIRPLAY_FEATURES));
    assert_eq!(dict["statusFlags"].as_unsigned_integer(), Some(bonjour::AIRPLAY_STATUS_FLAGS));
    assert!(dict.contains_key("deviceID"));
    let txt = dict["txtAirPlay"].as_data().unwrap();
    let expected = format!("features=0x{:X},0x0", bonjour::AIRPLAY_FEATURES);
    assert!(txt.windows(expected.len()).any(|s| s == expected.as_bytes()));
}

#[test]
fn encrypted_setup_reports_missing_fairplay_instead_of_mirroring() {
    let mut server = session();
    let client = Client::new(50);
    let first = server.crypto.handle_pair_verify_1(&client.first()).unwrap();
    server.crypto.handle_pair_verify_2(&client.second(&first, server.crypto.public_key_bytes(), false)).unwrap();
    let mut dict = plist::Dictionary::new();
    dict.insert("ekey".into(), plist::Value::Data(vec![0;72]));
    let mut encoded = Vec::new();
    plist::Value::Dictionary(dict).to_writer_binary(&mut encoded).unwrap();
    let response = server.handle_request(&request("SETUP", "/stream", encoded)).unwrap();
    assert!(response.starts_with(b"RTSP/1.0 501"));
    assert!(String::from_utf8_lossy(body(&response)).contains("FairPlay media key unwrap"));
    assert!(!server.is_mirroring);
    let response = server.handle_request(&request("RECORD", "/stream", vec![])).unwrap();
    assert!(response.starts_with(b"RTSP/1.0 455"));
}

#[test]
fn rtsp_fragmentation_pipeline_and_invalid_lengths() {
    let first = b"POST /pair-setup RTSP/1.0\r\nContent-Length: 4\r\n\r\nabcd";
    for end in 0..first.len() { assert!(parse_rtsp_request(&first[..end]).is_err()); }
    let second = b"OPTIONS * RTSP/1.0\r\nCSeq: 2\r\n\r\n";
    let pipeline = [first.as_slice(), second].concat();
    let parsed = parse_rtsp_request(&pipeline).unwrap();
    assert_eq!(parsed.body, b"abcd");
    assert_eq!(parse_rtsp_request(&pipeline[parsed.total_len..]).unwrap().method, "OPTIONS");
    for length in ["-1", "abc", "18446744073709551615", "1048577"] {
        let wire = format!("POST /pair-setup RTSP/1.0\r\nContent-Length: {length}\r\n\r\n");
        assert!(parse_rtsp_request(wire.as_bytes()).is_err());
    }
    assert!(parse_rtsp_request(b"POST /info RTSP/1.0\r\nContent-Length: 0\r\nContent-Length: 4\r\n\r\n").is_err());
}

#[test]
fn invalid_fairplay_mode_is_not_clamped_to_success() {
    let mut server = session();
    let mut data = b"FPLY\x03\x01\x01\x00\x00\x00\x00\x04\x00\x00\x04\x00".to_vec();
    let response = server.handle_request(&request("POST", "/fp-setup", data.clone())).unwrap();
    assert!(response.starts_with(b"RTSP/1.0 400"));
    data[14] = 0;
    let response = server.handle_request(&request("POST", "/fp-setup", data)).unwrap();
    assert_eq!(body(&response).len(), 142);
}

#[tokio::test]
async fn cancelling_listener_releases_idle_client_and_port() {
    // 仅 loopback，无 Bonjour、系统偏好修改或桌面 App 启动。
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = Arc::new(AirPlayServer {
        id: 999999, frame: Arc::new(Frame::default()),
        status: Arc::new(AtomicU8::new(0)), stopped: Arc::new(AtomicBool::new(false)),
        last_error: Arc::new(Mutex::new(String::new())), _advertiser: Mutex::new(None), task: Mutex::new(None),
        #[cfg(feature = "airplay-uxplay")]
        native: Mutex::new(None),
    });
    let runner = server.clone();
    let handle = tokio::spawn(async move {
        AirPlayServer::run_rtsp_loop(listener, runner, "Test", "02:00:00:00:00:01", 7100, vec![]).await;
    });
    let mut client = tokio::net::TcpStream::connect(address).await.unwrap();
    client.write_all(b"OPTIONS * RTSP/1.0\r\nCSeq: 1\r\n\r\n").await.unwrap();
    let mut buffer = [0;1024];
    let n = tokio::time::timeout(Duration::from_secs(2), client.read(&mut buffer)).await.unwrap().unwrap();
    assert!(buffer[..n].starts_with(b"RTSP/1.0 200"));
    *server.task.lock().unwrap() = Some(handle);
    server.stop();
    let n = tokio::time::timeout(Duration::from_secs(2), client.read(&mut buffer)).await.unwrap().unwrap();
    assert_eq!(n, 0);
    assert!(TcpListener::bind(address).await.is_ok());
}
