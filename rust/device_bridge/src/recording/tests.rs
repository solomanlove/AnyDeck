//! 固定编码数据、真实 MP4 读回与本地 scrcpy 4.0 socket 验证；不访问手机。
use super::{
    muxer::Muxer,
    protocol::{self, Event, Packet, CONFIG, KEY},
    Recording,
};
use std::{
    fs::File,
    io::Write,
    net::{TcpListener, TcpStream},
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, AtomicU8, Ordering},
        Arc, Mutex,
    },
    time::{Duration, Instant},
};

fn path(name: &str) -> PathBuf {
    let id = crate::NEXT_ID.fetch_add(1, Ordering::Relaxed);
    std::env::temp_dir().join(format!(
        "anydeck-record-test-{}-{id}-{name}.mp4",
        std::process::id()
    ))
}
fn packet(pts: u64, config: bool, key: bool, data: Vec<u8>) -> Packet {
    Packet {
        pts,
        config,
        key,
        data,
    }
}
fn config() -> Vec<u8> {
    let mut data = Vec::new();
    for nal in protocol::nals(include_bytes!("testdata/video.h264")).unwrap() {
        if nal[0] & 31 == 7 || nal[0] & 31 == 8 {
            data.extend_from_slice(&[0, 0, 0, 1]);
            data.extend_from_slice(nal);
            if nal[0] & 31 == 8 {
                break;
            }
        }
    }
    data
}
fn videos() -> Vec<Packet> {
    protocol::nals(include_bytes!("testdata/video.h264"))
        .unwrap()
        .into_iter()
        .filter(|nal| nal[0] & 31 == 5)
        .enumerate()
        .map(|(index, nal)| {
            let mut data = vec![0, 0, 0, 1];
            data.extend_from_slice(nal);
            packet(1_000_000 + index as u64 * 100_000, false, true, data)
        })
        .collect()
}
fn audios() -> Vec<Packet> {
    let mut data = &include_bytes!("testdata/audio.aac")[..];
    let mut packets = Vec::new();
    while data.len() >= 7 {
        let length =
            ((data[3] as usize & 3) << 11) | ((data[4] as usize) << 3) | (data[5] as usize >> 5);
        let pts = 1_020_000 + packets.len() as u64 * 1024 * 1_000_000 / 48000;
        packets.push(packet(pts, false, true, data[7..length].to_vec()));
        data = &data[length..];
    }
    packets
}

#[test]
fn real_h264_aac_mp4_preserves_tracks_samples_and_audio_offset() {
    let output = path("av");
    let mut muxer = Muxer::new(&output).unwrap();
    muxer.push(Event::Size(320, 240)).unwrap();
    muxer
        .push(Event::Video(packet(0, true, false, config())))
        .unwrap();
    muxer
        .push(Event::Audio(packet(0, true, false, vec![0x11, 0x90])))
        .unwrap();
    let video_count = videos().len() as u32;
    let audio_count = audios().len() as u32;
    for video in videos() {
        muxer.push(Event::Video(video)).unwrap();
    }
    for audio in audios() {
        muxer.push(Event::Audio(audio)).unwrap();
    }
    assert!(muxer.ready());
    muxer.finish(&output, true).unwrap();
    let file = File::open(&output).unwrap();
    let mut reader = mp4::Mp4Reader::read_header(file, output.metadata().unwrap().len()).unwrap();
    assert_eq!(reader.tracks().len(), 2);
    assert_eq!(reader.sample_count(1).unwrap(), video_count);
    assert_eq!(reader.sample_count(2).unwrap(), audio_count);
    assert_eq!(reader.tracks()[&1].width(), 320);
    assert_eq!(reader.tracks()[&1].height(), 240);
    assert_eq!(
        reader.read_sample(2, 1).unwrap().unwrap().rendering_offset,
        1800
    );
    assert!(reader.read_sample(1, 1).unwrap().unwrap().is_sync);
    if let Ok(destination) = std::env::var("ANYDECK_RECORD_TEST_OUTPUT") {
        std::fs::copy(&output, destination).unwrap();
    }
    std::fs::remove_file(output).unwrap();
}

#[test]
fn disabled_audio_and_partial_finalization_remain_readable_without_publishing() {
    let output = path("partial");
    let mut muxer = Muxer::new(&output).unwrap();
    let partial = muxer.partial.clone();
    muxer.push(Event::Size(320, 240)).unwrap();
    muxer.push(Event::AudioDisabled).unwrap();
    muxer
        .push(Event::Video(packet(0, true, false, config())))
        .unwrap();
    for video in videos() {
        muxer.push(Event::Video(video)).unwrap();
    }
    assert!(muxer.ready());
    muxer.finish(&output, false).unwrap();
    assert!(!output.exists());
    let reader = mp4::Mp4Reader::read_header(
        File::open(&partial).unwrap(),
        partial.metadata().unwrap().len(),
    )
    .unwrap();
    assert_eq!(reader.tracks().len(), 1);
    assert_eq!(reader.sample_count(1).unwrap(), 10);
    std::fs::remove_file(partial).unwrap();
}

#[test]
fn destination_is_not_overwritten_and_dynamic_dimensions_are_rejected() {
    let output = path("guard");
    std::fs::write(&output, b"existing").unwrap();
    assert!(Muxer::new(&output).is_err());
    assert_eq!(std::fs::read(&output).unwrap(), b"existing");
    std::fs::remove_file(&output).unwrap();
    let mut muxer = Muxer::new(&output).unwrap();
    let partial = muxer.partial.clone();
    muxer.push(Event::Size(320, 240)).unwrap();
    muxer
        .push(Event::Video(packet(0, true, false, config())))
        .unwrap();
    muxer.push(Event::Video(videos().remove(0))).unwrap();
    assert!(muxer.push(Event::Size(240, 320)).is_err());
    muxer.finish(&output, false).unwrap();
    std::fs::remove_file(partial).unwrap();
}

#[test]
fn timestamp_regression_and_unbounded_startup_audio_are_rejected() {
    let output = path("bounds");
    let mut muxer = Muxer::new(&output).unwrap();
    let partial = muxer.partial.clone();
    for _ in 0..128 {
        muxer
            .push(Event::Audio(packet(1, false, false, vec![1])))
            .unwrap();
    }
    assert!(muxer
        .push(Event::Audio(packet(1, false, false, vec![1])))
        .is_err());
    drop(muxer);
    std::fs::remove_file(partial).unwrap();
    let mut muxer = Muxer::new(&output).unwrap();
    let partial = muxer.partial.clone();
    muxer.push(Event::Size(320, 240)).unwrap();
    muxer
        .push(Event::Video(packet(0, true, false, config())))
        .unwrap();
    muxer.push(Event::Video(videos().remove(0))).unwrap();
    assert!(muxer.push(Event::Video(videos().remove(0))).is_err());
    drop(muxer);
    std::fs::remove_file(partial).unwrap();
}

fn pair() -> (TcpStream, TcpStream) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let client = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
    client
        .set_read_timeout(Some(Duration::from_millis(50)))
        .unwrap();
    (client, listener.accept().unwrap().0)
}
#[test]
fn fragmented_headers_and_oversized_packets_are_handled_before_allocation() {
    let (mut client, mut server) = pair();
    let thread = std::thread::spawn(move || {
        for byte in (KEY | 100)
            .to_be_bytes()
            .into_iter()
            .chain(3u32.to_be_bytes())
            .chain([1, 2, 3])
        {
            server.write_all(&[byte]).unwrap();
        }
    });
    let Event::Video(packet) = protocol::read(&mut client, &AtomicBool::new(false), true).unwrap()
    else {
        panic!()
    };
    assert_eq!(packet.pts, 100);
    assert!(packet.key);
    assert_eq!(packet.data, [1, 2, 3]);
    thread.join().unwrap();
    let (mut client, mut server) = pair();
    server.write_all(&[0; 8]).unwrap();
    server
        .write_all(&((protocol::MAX_PACKET + 1) as u32).to_be_bytes())
        .unwrap();
    assert!(protocol::read(&mut client, &AtomicBool::new(false), true)
        .err()
        .unwrap()
        .contains("length"));
}

fn wire(packet: &Packet) -> Vec<u8> {
    let flags =
        packet.pts | if packet.config { CONFIG } else { 0 } | if packet.key { KEY } else { 0 };
    let mut bytes = flags.to_be_bytes().to_vec();
    bytes.extend_from_slice(&(packet.data.len() as u32).to_be_bytes());
    bytes.extend_from_slice(&packet.data);
    bytes
}

#[test]
fn two_socket_receiver_stops_and_finalizes_real_audio_video() {
    let output = path("socket");
    let mut muxer = Muxer::new(&output).unwrap();
    let (video, mut video_peer) = pair();
    let (audio, mut audio_peer) = pair();
    let state = Arc::new(Recording {
        serial: "fixture".into(),
        stopped: AtomicBool::new(false),
        status: AtomicU8::new(0),
        sockets: Mutex::new(vec![video.try_clone().unwrap(), audio.try_clone().unwrap()]),
        error: Mutex::new(String::new()),
    });
    std::thread::scope(|scope| {
        let consumer = scope.spawn(|| super::receiver::receive(video, audio, &state, &mut muxer));
        video_peer.write_all(b"h264").unwrap();
        video_peer
            .write_all(&[0x80, 0, 0, 0, 0, 0, 1, 64, 0, 0, 0, 240])
            .unwrap();
        video_peer
            .write_all(&wire(&packet(0, true, false, config())))
            .unwrap();
        audio_peer.write_all(&[0, b'a', b'a', b'c']).unwrap();
        audio_peer
            .write_all(&wire(&packet(0, true, false, vec![0x11, 0x90])))
            .unwrap();
        let mut audio_packets = audios().into_iter();
        for video in videos() {
            video_peer.write_all(&wire(&video)).unwrap();
            for _ in 0..4 {
                if let Some(a) = audio_packets.next() {
                    audio_peer.write_all(&wire(&a)).unwrap();
                }
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        let deadline = Instant::now() + Duration::from_secs(3);
        while state.status.load(Ordering::Acquire) != 1 && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(10));
        }
        assert_eq!(state.status.load(Ordering::Acquire), 1, "{}", state.error());
        state.cancel();
        consumer.join().unwrap().unwrap();
    });
    muxer.finish(&output, true).unwrap();
    assert!(output.metadata().unwrap().len() > 1000);
    std::fs::remove_file(output).unwrap();
}

#[test]
fn invalid_aac_and_annex_b_are_rejected() {
    assert!(protocol::nals(&[1, 2, 3]).is_err());
    assert!(protocol::nals(&[0, 0, 1]).is_err());
    assert_eq!(
        protocol::nals(&[0, 0, 1, 0x65, 1]).unwrap(),
        vec![&[0x65, 1][..]]
    );
    let output = path("bad-aac");
    let mut muxer = Muxer::new(&output).unwrap();
    let partial = muxer.partial.clone();
    assert!(muxer
        .push(Event::Audio(packet(0, true, false, vec![0xff, 0xff])))
        .is_err());
    assert!(muxer.finish(&output, false).is_err());
    assert!(!partial.exists());
}

#[cfg(unix)]
#[test]
fn ffi_recording_uses_only_adb_and_cleans_transport_before_reporting_stopped() {
    use std::{ffi::CString, os::unix::fs::PermissionsExt};
    let output = path("ffi");
    let script = output.with_extension("adb");
    let log = output.with_extension("log");
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    std::fs::write(&script, format!("#!/bin/sh\nprintf '%s\\n' \"$*\" >> '{}'\ncase \"$*\" in\n*getprop*) printf '33\\n';;\n*'forward tcp:0'*) printf '{port}\\n';;\n*app_process*) exec /bin/sleep 30;;\nesac\n", log.display())).unwrap();
    std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o700)).unwrap();
    listener.set_nonblocking(true).unwrap();
    let peer = std::thread::spawn(move || {
        let accept = || {
            let deadline = Instant::now() + Duration::from_secs(5);
            loop {
                if let Ok(pair) = listener.accept() {
                    pair.0.set_nonblocking(false).unwrap();
                    return pair.0;
                }
                assert!(Instant::now() < deadline, "recording socket not connected");
                std::thread::sleep(Duration::from_millis(5));
            }
        };
        let mut video = accept();
        video.write_all(&[0]).unwrap();
        let mut audio = accept();
        video.write_all(b"h264").unwrap();
        video
            .write_all(&[0x80, 0, 0, 0, 0, 0, 1, 64, 0, 0, 0, 240])
            .unwrap();
        video
            .write_all(&wire(&packet(0, true, false, config())))
            .unwrap();
        audio.write_all(&[0, b'a', b'a', b'c']).unwrap();
        audio
            .write_all(&wire(&packet(0, true, false, vec![0x11, 0x90])))
            .unwrap();
        let _ = video.write_all(&wire(&videos().remove(0)));
        let _ = audio.write_all(&wire(&audios().remove(0)));
        use std::io::Read;
        let _ = video.set_read_timeout(Some(Duration::from_secs(5)));
        let _ = video.read(&mut [0]);
    });
    let args = [
        script.to_str().unwrap(),
        "fixture device:123",
        "server with spaces.jar",
        output.to_str().unwrap(),
    ]
    .map(|s| CString::new(s).unwrap());
    let id = unsafe {
        super::anydeck_start_recording(
            args[0].as_ptr(),
            args[1].as_ptr(),
            args[2].as_ptr(),
            args[3].as_ptr(),
        )
    };
    assert_ne!(id, 0);
    let wait = |expected| {
        let deadline = Instant::now() + Duration::from_secs(5);
        while crate::anydeck_status(id) != expected && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(10));
        }
        assert_eq!(
            crate::anydeck_status(id),
            expected,
            "{}",
            super::get(id).unwrap().error()
        );
    };
    wait(1);
    let duplicate = unsafe {
        super::anydeck_start_recording(
            args[0].as_ptr(),
            args[1].as_ptr(),
            args[2].as_ptr(),
            args[3].as_ptr(),
        )
    };
    assert_eq!(duplicate, 0);
    crate::anydeck_stop(id);
    assert!(super::get(id).unwrap().stopped.load(Ordering::Acquire));
    wait(2);
    assert!(output.exists());
    assert!(!output.with_extension("partial.mp4").exists());
    let commands = std::fs::read_to_string(&log).unwrap();
    assert!(commands.contains("com.genymobile.scrcpy.Server 4.0"));
    assert!(commands.contains("audio_codec=aac"));
    assert!(commands.contains("capture_orientation=@"));
    assert!(!commands.contains("max_size="));
    assert!(commands.contains("forward --remove tcp:"));
    assert!(commands.contains("shell rm -f /data/local/tmp/anydeck-"));
    crate::anydeck_release(id);
    assert!(super::get(id).is_none());
    peer.join().unwrap();
    for file in [output, script, log] {
        std::fs::remove_file(file).unwrap();
    }
}

#[test]
fn finalization_does_not_overwrite_a_destination_created_while_recording() {
    let output = path("late-destination");
    let mut muxer = Muxer::new(&output).unwrap();
    let partial = muxer.partial.clone();
    muxer.push(Event::Size(320, 240)).unwrap();
    muxer.push(Event::AudioDisabled).unwrap();
    muxer
        .push(Event::Video(packet(0, true, false, config())))
        .unwrap();
    muxer.push(Event::Video(videos().remove(0))).unwrap();
    std::fs::write(&output, b"owned by another writer").unwrap();
    assert!(muxer.finish(&output, true).is_err());
    assert_eq!(std::fs::read(&output).unwrap(), b"owned by another writer");
    let reader = mp4::Mp4Reader::read_header(
        File::open(&partial).unwrap(),
        partial.metadata().unwrap().len(),
    )
    .unwrap();
    assert_eq!(reader.sample_count(1).unwrap(), 1);
    std::fs::remove_file(output).unwrap();
    std::fs::remove_file(partial).unwrap();
}
