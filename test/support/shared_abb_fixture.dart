import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:any_deck/core/device_share/share_socket_reader.dart';
import 'package:crypto/crypto.dart';

/// 模拟 ABB 的 Shell v2 安装输入；只保留一个 64 KiB 块和 SHA-256 状态。
class SharedAbbFixture {
  SharedAbbFixture(this.size);

  final int size;
  final _firstPayload = Completer<void>();
  int receivedBytes = 0;
  String? request;
  Digest? receivedHash;

  String get _service => [
    'abb:package',
    'install-write',
    '-S',
    '$size',
    'test-session',
    'base.apk',
    '-',
    '',
  ].join('\u0000');

  /// Source 端读取 stdin/EOF 帧，按安装声明的精确字节数回应结果。
  Future<void> handle(
    String service,
    Socket socket,
    ShareSocketReader reader,
  ) async {
    if (service.startsWith('shell,v2')) {
      socket.add(_frame(1, utf8.encode('AnyDeck concurrent shell\n')));
      socket.add(_frame(3, [0]));
      return;
    }
    if (!service.startsWith('abb:')) {
      throw FormatException('Unexpected ABB fixture service: $service');
    }
    request = service;
    final digest = _DigestSink();
    final hash = sha256.startChunkedConversion(digest);
    while (true) {
      final header = await reader.read(5);
      final length = ByteData.sublistView(header).getUint32(1, Endian.little);
      if (header[0] == 4 && length == 0) break;
      if (header[0] != 0 || length > 65536 || receivedBytes + length > size) {
        throw const FormatException('Invalid ABB stdin frame');
      }
      final data = await reader.read(length);
      hash.add(data);
      receivedBytes += data.length;
      if (!_firstPayload.isCompleted) _firstPayload.complete();
    }
    hash.close();
    receivedHash = digest.value;
    if (receivedBytes != size) {
      throw const FormatException('Incomplete ABB install payload');
    }
    socket.add(_frame(1, utf8.encode('Success\n')));
    socket.add(_frame(3, [0]));
  }

  /// 通过真正的接收端 ADB Smart Socket 发 ABB 请求，首块到达后验证并发查询。
  Future<({Digest sentHash, String stdout, int exitCode})> upload(
    int adbPort,
    String deviceId, {
    required Future<void> Function() duringUpload,
  }) async {
    final socket = await Socket.connect('127.0.0.1', adbPort);
    final reader = ShareSocketReader(socket);
    final digest = _DigestSink();
    final hash = sha256.startChunkedConversion(digest);
    try {
      await _request(socket, reader, 'host:transport:$deviceId');
      await _request(socket, reader, _service);
      final block = Uint8List.fromList(List.generate(65536, (i) => i % 251));
      for (var offset = 0; offset < size; offset += block.length) {
        final length = (size - offset).clamp(0, block.length);
        final data = Uint8List.sublistView(block, 0, length);
        hash.add(data);
        socket.add(_frame(0, data));
        // 每块 flush，避免 260 MiB 一次堆入 IOSink 或测试内存。
        await socket.flush();
        if (offset == 0) {
          await _firstPayload.future.timeout(const Duration(seconds: 5));
          await duringUpload();
        }
      }
      hash.close();
      socket.add(_frame(4, const []));
      await socket.flush();
      final output = BytesBuilder();
      while (true) {
        final header = await reader.read(5);
        final length = ByteData.sublistView(header).getUint32(1, Endian.little);
        if (length > 65536) {
          throw const FormatException('Invalid ABB output frame');
        }
        final data = await reader.read(length);
        if (header[0] == 3 && length == 1) {
          return (
            sentHash: digest.value!,
            stdout: utf8.decode(output.takeBytes()),
            exitCode: data.single,
          );
        }
        if (header[0] != 1) {
          throw const FormatException('Unexpected ABB output channel');
        }
        output.add(data);
      }
    } finally {
      socket.destroy();
      await reader.cancel();
    }
  }

  Future<void> _request(
    Socket socket,
    ShareSocketReader reader,
    String service,
  ) async {
    final data = utf8.encode(service);
    socket.add(ascii.encode(data.length.toRadixString(16).padLeft(4, '0')));
    socket.add(data);
    await socket.flush();
    if (ascii.decode(await reader.read(4)) != 'OKAY') {
      throw const SocketException('ADB rejected fixture service');
    }
  }

  Uint8List _frame(int channel, List<int> data) {
    final frame = Uint8List(data.length + 5)..[0] = channel;
    ByteData.sublistView(frame).setUint32(1, data.length, Endian.little);
    frame.setRange(5, frame.length, data);
    return frame;
  }
}

/// ChunkedConversion 的唯一 Digest，不保留输入字节。
class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
