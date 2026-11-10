//! 两路压缩包收取与单写线程；有界背压吸收传输突发，禁止无界积压或静默丢包。
use super::{
    muxer::Muxer,
    protocol::{self, Event},
    Recording,
};
use crate::{adb::Transport, stream};
use std::{
    net::{SocketAddr, TcpStream},
    path::PathBuf,
    sync::{
        atomic::Ordering,
        mpsc::{self, SyncSender, TrySendError},
        Arc,
    },
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

pub fn run(
    adb: String,
    serial: String,
    jar: String,
    path: PathBuf,
    id: u64,
    state: &Arc<Recording>,
) -> Result<(), String> {
    let mut muxer = Muxer::new(&path)?;
    let partial = muxer.partial.clone();
    let outcome = (|| {
        let token = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|e| e.to_string())?
            .as_nanos() as u64
            ^ id;
        let mut transport = Transport::start(adb, serial, jar, 5, token, &state.stopped)?;
        let (video, audio) = connect(transport.port, &mut transport, state)?;
        let result = receive(video, audio, state, &mut muxer);
        muxer.end_capture();
        result
    })();
    if let Err(error) = outcome {
        state.fail(error);
    }
    let success = state.error().is_empty();
    let finish = muxer.finish(&path, success);
    if let Err(error) = finish {
        let previous = state.error();
        let error = if previous.is_empty() {
            error
        } else {
            format!("{previous}; {error}")
        };
        return Err(if partial.exists() {
            format!("{error}; partial file: {}", partial.display())
        } else {
            error
        });
    }
    if success {
        Ok(())
    } else {
        Err(format!(
            "{}; partial file: {}",
            state.error(),
            partial.display()
        ))
    }
}

fn connect(
    port: u16,
    transport: &mut Transport,
    state: &Recording,
) -> Result<(TcpStream, TcpStream), String> {
    let address = SocketAddr::from(([127, 0, 0, 1], port));
    let deadline = Instant::now() + Duration::from_secs(15);
    while !state.stopped.load(Ordering::Acquire) && Instant::now() < deadline && transport.alive() {
        if let Ok(mut video) = TcpStream::connect_timeout(&address, Duration::from_millis(300)) {
            video
                .set_read_timeout(Some(Duration::from_millis(200)))
                .map_err(|e| e.to_string())?;
            state
                .sockets
                .lock()
                .map_err(|_| "Recording socket lock poisoned")?
                .push(video.try_clone().map_err(|e| e.to_string())?);
            let mut dummy = [1];
            if stream::read(&mut video, &mut dummy, &state.stopped).is_ok() && dummy == [0] {
                let audio = TcpStream::connect_timeout(&address, Duration::from_secs(2))
                    .map_err(|e| e.to_string())?;
                audio
                    .set_read_timeout(Some(Duration::from_millis(200)))
                    .map_err(|e| e.to_string())?;
                state
                    .sockets
                    .lock()
                    .map_err(|_| "Recording socket lock poisoned")?
                    .push(audio.try_clone().map_err(|e| e.to_string())?);
                return Ok((video, audio));
            }
            state
                .sockets
                .lock()
                .map_err(|_| "Recording socket lock poisoned")?
                .clear();
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    Err("Recording server connection cancelled or timed out".into())
}

pub(super) fn receive(
    video: TcpStream,
    audio: TcpStream,
    state: &Arc<Recording>,
    muxer: &mut Muxer,
) -> Result<(), String> {
    // 队列最多 8 包，两个收包线程各暂存 1 包；持续写盘阻塞才终止此独立会话。
    let (sender, receiver) = mpsc::sync_channel(8);
    std::thread::scope(|scope| {
        for (socket, video) in [(video, true), (audio, false)] {
            let tx = sender.clone();
            scope.spawn(move || {
                if let Err(error) = read_stream(socket, video, &tx, state) {
                    if !state.stopped.load(Ordering::Acquire) {
                        state.fail(error);
                    }
                }
            });
        }
        drop(sender);
        let startup = Instant::now() + Duration::from_secs(15);
        loop {
            match receiver.recv_timeout(Duration::from_millis(100)) {
                Ok(event) => {
                    if let Err(error) = muxer.push(event) {
                        state.fail(error);
                        break;
                    }
                    if muxer.ready() && !state.stopped.load(Ordering::Acquire) {
                        state.status.store(1, Ordering::Release);
                    }
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
                Err(mpsc::RecvTimeoutError::Timeout) => {}
            }
            if state.status.load(Ordering::Acquire) == 0 && Instant::now() >= startup {
                state.fail("Timed out waiting for recording keyframe/audio".into());
                break;
            }
        }
        // 先停止/关闭 socket 再 join；scope 保证不会遗留收包线程。
        state.cancel();
        drop(receiver);
    });
    if state.error().is_empty() {
        Ok(())
    } else {
        Err(state.error())
    }
}

fn read_stream(
    mut socket: TcpStream,
    video: bool,
    sender: &SyncSender<Event>,
    state: &Recording,
) -> Result<(), String> {
    let codec = protocol::codec(&mut socket, &state.stopped)?;
    if !video && codec == [0; 4] {
        return send(sender, Event::AudioDisabled, &state.stopped);
    }
    if codec == [0, 0, 0, 1] {
        return Err("Recording encoder configuration failed on device".into());
    }
    if codec
        != if video {
            *b"h264"
        } else {
            [0, b'a', b'a', b'c']
        }
    {
        return Err("Unexpected recording codec".into());
    }
    while !state.stopped.load(Ordering::Acquire) {
        send(
            sender,
            protocol::read(&mut socket, &state.stopped, video)?,
            &state.stopped,
        )?;
    }
    Ok(())
}

fn send(
    sender: &SyncSender<Event>,
    event: Event,
    stopped: &std::sync::atomic::AtomicBool,
) -> Result<(), String> {
    send_until(
        sender,
        event,
        stopped,
        Instant::now() + Duration::from_secs(2),
    )
}

/// 无线 ADB 会批量送达压缩包；满队列时保留当前包并等待写线程，不丢帧。
fn send_until(
    sender: &SyncSender<Event>,
    mut event: Event,
    stopped: &std::sync::atomic::AtomicBool,
    deadline: Instant,
) -> Result<(), String> {
    loop {
        if stopped.load(Ordering::Acquire) {
            return Err("Recording queue wait cancelled".into());
        }
        match sender.try_send(event) {
            Ok(()) => return Ok(()),
            Err(TrySendError::Disconnected(_)) => return Err("Recording writer closed".into()),
            Err(TrySendError::Full(pending)) => event = pending,
        }
        if Instant::now() >= deadline {
            return Err("Recording writer stalled: queue wait timed out".into());
        }
        std::thread::sleep(Duration::from_millis(5));
    }
}

#[cfg(test)]
#[test]
fn stalled_writer_fails_explicitly_instead_of_dropping_compressed_packets() {
    let (sender, _receiver) = mpsc::sync_channel(8);
    for _ in 0..8 {
        sender.try_send(Event::AudioDisabled).ok().unwrap();
    }
    let stopped = std::sync::atomic::AtomicBool::new(false);
    assert!(send_until(
        &sender,
        Event::AudioDisabled,
        &stopped,
        Instant::now() + Duration::from_millis(30)
    )
    .unwrap_err()
    .contains("writer stalled"));
}

#[cfg(test)]
#[test]
fn temporary_burst_waits_and_preserves_packet_order() {
    let (sender, receiver) = mpsc::sync_channel(1);
    sender.try_send(Event::Size(10, 20)).ok().unwrap();
    let writer = std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(30));
        assert!(matches!(receiver.recv().unwrap(), Event::Size(10, 20)));
        assert!(matches!(receiver.recv().unwrap(), Event::Size(30, 40)));
    });
    let stopped = std::sync::atomic::AtomicBool::new(false);
    send(&sender, Event::Size(30, 40), &stopped).unwrap();
    writer.join().unwrap();
}

#[cfg(test)]
#[test]
fn queue_wait_can_be_cancelled_and_closed_writer_is_distinct() {
    let (sender, receiver) = mpsc::sync_channel(1);
    sender.try_send(Event::AudioDisabled).ok().unwrap();
    let stopped = std::sync::atomic::AtomicBool::new(false);
    std::thread::scope(|scope| {
        scope.spawn(|| {
            std::thread::sleep(Duration::from_millis(20));
            stopped.store(true, Ordering::Release);
        });
        assert!(send(&sender, Event::AudioDisabled, &stopped)
            .unwrap_err()
            .contains("cancelled"));
    });
    drop(receiver);
    stopped.store(false, Ordering::Release);
    assert!(send(&sender, Event::AudioDisabled, &stopped)
        .unwrap_err()
        .contains("writer closed"));
}
