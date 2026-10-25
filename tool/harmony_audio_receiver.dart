import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

const _port = 26733;
const _headerLength = 16;

/// HarmonyOS Companion 的 PCM 预览接收端：先监听，再建立 HDC 反向端口。
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      '用法: dart run tool/harmony_audio_receiver.dart <HDC-USB设备ID>',
    );
    exitCode = 64;
    return;
  }
  final hdc = Platform.environment['HDC'] ?? 'hdc';
  final deviceId = args.single;
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, _port);
  Process? player;
  Socket? client;
  try {
    final forward = await Process.run(hdc, [
      '-t',
      deviceId,
      'rport',
      'tcp:$_port',
      'tcp:$_port',
    ]);
    if (forward.exitCode != 0 ||
        '${forward.stdout}${forward.stderr}'.contains('[Fail]')) {
      throw StateError('HDC 反向端口创建失败: ${forward.stdout}${forward.stderr}');
    }
    stdout.writeln('等待设备端连接 127.0.0.1:$_port；在 Companion 中点击音频开始。');
    client = await server.first.timeout(const Duration(minutes: 2));
    player = await Process.start('ffplay', [
      '-nodisp',
      '-autoexit',
      '-loglevel',
      'error',
      '-f',
      's16le',
      '-ar',
      '48000',
      '-ac',
      '2',
      '-i',
      'pipe:0',
    ]);
    final playerInput = player.stdin;
    final done = Completer<void>();
    var pending = Uint8List(0);
    var headerRead = false;
    int? frameLength;
    client.listen(
      (chunk) {
        final merged = Uint8List(pending.length + chunk.length)
          ..setRange(0, pending.length, pending)
          ..setRange(pending.length, pending.length + chunk.length, chunk);
        pending = merged;
        while (true) {
          if (!headerRead) {
            if (pending.length < _headerLength) break;
            final magic = String.fromCharCodes(pending.take(7));
            final data = ByteData.sublistView(pending);
            final sampleRate = data.getUint32(8, Endian.little);
            if (magic != 'ADBAUD1' ||
                sampleRate != 48000 ||
                pending[12] != 2 ||
                pending[13] != 2) {
              client?.destroy();
              done.completeError(const FormatException('设备端 PCM 协议头不匹配'));
              return;
            }
            stdout.writeln(pending[14] == 1 ? '麦克风 PCM 已连接' : '设备内音频 PCM 已连接');
            pending = Uint8List.sublistView(pending, _headerLength);
            headerRead = true;
          }
          if (frameLength == null) {
            if (pending.length < 4) break;
            frameLength = ByteData.sublistView(
              pending,
            ).getUint32(0, Endian.little);
            pending = Uint8List.sublistView(pending, 4);
            if (frameLength == 0 || frameLength! > 1024 * 1024) {
              client?.destroy();
              done.completeError(const FormatException('设备端 PCM 帧长度无效'));
              return;
            }
          }
          if (pending.length < frameLength!) break;
          playerInput.add(Uint8List.sublistView(pending, 0, frameLength));
          pending = Uint8List.sublistView(pending, frameLength!);
          frameLength = null;
        }
      },
      onError: done.completeError,
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future;
  } finally {
    client?.destroy();
    await player?.stdin.close();
    player?.kill();
    await Process.run(hdc, [
      '-t',
      deviceId,
      'fport',
      'rm',
      'tcp:$_port',
      'tcp:$_port',
    ]);
    await server.close();
  }
}
