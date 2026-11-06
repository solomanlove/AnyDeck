import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../share_socket_reader.dart';
import 'adb_bridge_stream.dart';
import 'adb_packet.dart';
import 'shared_adb_backend.dart';
import 'shared_adb_reverse.dart';

/// 已经通过 TLS/分享码认证的单设备 ADB Transport，不暴露宿主 Smart Socket。
class SharedAdbPeer {
  SharedAdbPeer(this.socket, this.reader, this.backend) {
    _reverse = SharedAdbReverse(backend, _openReverse);
  }
  final Socket socket;
  final ShareSocketReader reader;
  final SharedAdbBackend backend;
  final _streams = <int, AdbBridgeStream>{};
  late final SharedAdbReverse _reverse;
  int _nextId = 0, _payloadLimit = 4096;
  bool _closed = false;
  Future<void>? _closing;

  Future<void> _send(AdbPacket packet) async {
    if (_closed) return;
    socket.add(packet.encode());
    await socket.flush().timeout(const Duration(seconds: 15));
  }

  /// 仅开放设备服务；尤其禁止 host:*、transport 重选与宿主全局 Server 控制。
  static bool allowsService(String name) {
    if (name.length > 4096) return false;
    // ABB 使用 NUL 分隔 PackageManager 参数；其余服务禁止 NUL，防止请求混淆。
    if (name.startsWith('abb:') || name.startsWith('abb_exec:')) return true;
    if (name.contains('\u0000')) return false;
    return name == 'sync:' ||
        name == 'track-jdwp' ||
        name == 'track-app' ||
        name.startsWith('track-app:') ||
        [
          'shell:',
          'shell,',
          'exec:',
          'abb:',
          'abb_exec:',
          'localabstract:',
          'localfilesystem:',
          'jdwp:',
          'tcp:',
        ].any(name.startsWith);
  }

  Future<void> run() async {
    try {
      final first = await AdbPacket.read(
        reader,
      ).timeout(const Duration(seconds: 10));
      if (first.command != AdbPacket.cnxn ||
          first.arg1 < 4096 ||
          (first.arg0 != 0x01000000 && first.arg0 != 0x01000001)) {
        throw const FormatException('Invalid ADB handshake');
      }
      _payloadLimit = first.arg1.clamp(4096, AdbPacket.maxPayload);
      final banner = await backend.banner();
      await _send(
        AdbPacket(
          AdbPacket.cnxn,
          0x01000001,
          _payloadLimit,
          Uint8List.fromList(utf8.encode(banner)),
        ),
      );
      while (!_closed) {
        final packet = await AdbPacket.read(reader);
        switch (packet.command) {
          case AdbPacket.open:
            await _open(packet);
          case AdbPacket.okay:
            _streams[packet.arg1]?.acknowledge(packet.arg0);
          case AdbPacket.wrte:
            final stream = _streams[packet.arg1];
            if (stream != null) {
              try {
                await stream.write(packet);
              } catch (_) {
                stream.close();
              }
            }
          case AdbPacket.clse:
            final stream = _streams[packet.arg1];
            if (stream?.remoteId == packet.arg0) stream?.close();
          default:
            throw const FormatException('Unexpected ADB packet');
        }
      }
    } finally {
      await close();
    }
  }

  Future<void> _open(AdbPacket packet) async {
    Future<void> reject() => _send(AdbPacket(AdbPacket.clse, 0, packet.arg0));
    if (_streams.length >= 64 ||
        packet.arg0 == 0 ||
        packet.arg1 != 0 ||
        packet.data.isEmpty ||
        packet.data.length > 4097 ||
        packet.data.last != 0 ||
        _streams.values.any((stream) => stream.remoteId == packet.arg0)) {
      await reject();
      return;
    }
    final name = utf8.decode(packet.data.sublist(0, packet.data.length - 1));
    if (name.startsWith('reverse:') &&
        name.length <= 128 &&
        !name.contains('\u0000')) {
      // Reverse 控制结果也是正常 ADB Stream，使用内存 Socket 对避免另一套流控。
      final pair = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accept = pair.first;
      final writer = await Socket.connect(
        InternetAddress.loopbackIPv4,
        pair.port,
      );
      final socket = await accept;
      await pair.close();
      final readable = SharedAdbConnection(socket, ShareSocketReader(socket));
      _addStream(readable, packet.arg0);
      unawaited(
        () async {
          try {
            writer.add(await _reverse.handle(name));
            await writer.flush();
          } finally {
            await writer.close();
          }
        }().catchError((_) {
          writer.destroy();
        }),
      );
      return;
    }
    if (!allowsService(name)) {
      await reject();
      return;
    }
    try {
      final connection = await backend.open(name);
      if (_closed) {
        connection.close();
        return;
      }
      _addStream(connection, packet.arg0);
    } catch (_) {
      await reject();
    }
  }

  void _addStream(SharedAdbConnection connection, int remoteId) {
    final id = ++_nextId;
    final stream = AdbBridgeStream(
      id: id,
      remoteId: remoteId,
      connection: connection,
      payloadLimit: _payloadLimit,
      send: _send,
      onClose: () => _streams.remove(id),
    );
    _streams[id] = stream;
    unawaited(
      _send(
        AdbPacket(AdbPacket.okay, id, remoteId),
      ).then((_) => stream.pump()).catchError((_) {
        stream.close();
      }),
    );
  }

  void _openReverse(String destination, Socket connection) {
    if (_closed || _streams.length >= 64) {
      connection.destroy();
      return;
    }
    final id = ++_nextId;
    final stream = AdbBridgeStream(
      id: id,
      remoteId: 0,
      connection: SharedAdbConnection(
        connection,
        ShareSocketReader(connection),
      ),
      payloadLimit: _payloadLimit,
      send: _send,
      onClose: () => _streams.remove(id),
    );
    _streams[id] = stream;
    // pump 先安装初始 ACK 等待者，再发送 OPEN，避免快速回包丢失。
    unawaited(stream.pump(waitForOpen: true));
    unawaited(
      _send(
        AdbPacket(
          AdbPacket.open,
          id,
          0,
          Uint8List.fromList(utf8.encode('$destination\u0000')),
        ),
      ).catchError((_) {
        stream.close();
      }),
    );
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    socket.destroy();
    unawaited(reader.cancel());
    for (final stream in _streams.values.toList()) {
      stream.close();
    }
    await _reverse.close();
  }
}
