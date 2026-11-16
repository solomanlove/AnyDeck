import 'dart:async';

import 'adb_packet.dart';
import 'shared_adb_backend.dart';

/// 一条 ADB Stream 最多保留一个待确认 payload，避免慢 Wi-Fi 导致无限积压。
class AdbBridgeStream {
  AdbBridgeStream({
    required this.id,
    required this.remoteId,
    required this.connection,
    required this.payloadLimit,
    required this.send,
    required this.onClose,
  });

  final int id, payloadLimit;
  int remoteId;
  final SharedAdbConnection connection;
  final Future<void> Function(AdbPacket, {void Function()? beforeWrite}) send;
  final void Function() onClose;
  Completer<void>? _ack;
  bool _closed = false, _writing = false;

  void acknowledge(int peerId) {
    if (remoteId == 0) remoteId = peerId;
    if (peerId != remoteId) return;
    final ack = _ack;
    if (ack != null && !ack.isCompleted) ack.complete();
  }

  Future<void> pump({bool waitForOpen = false}) async {
    try {
      if (waitForOpen) {
        _ack = Completer<void>();
        await _ack!.future.timeout(const Duration(seconds: 15));
      }
      while (!_closed) {
        final data = await connection.reader.readChunk(payloadLimit);
        if (data == null || _closed) break;
        _ack = Completer<void>();
        await send(AdbPacket(AdbPacket.wrte, id, remoteId, data));
        await _ack!.future.timeout(const Duration(seconds: 30));
      }
    } catch (_) {
      // 单条流异常只关闭该服务；设备拔线由共享会话监听统一回收。
    } finally {
      close();
    }
  }

  /// Legacy ADB 每流仅接纳一块未确认输入；慢写入不得阻塞整个 Transport。
  void write(AdbPacket packet) {
    if (_closed || packet.arg0 != remoteId) return;
    if (_writing) {
      close();
      return;
    }
    _writing = true;
    unawaited(_write(packet));
  }

  Future<void> _write(AdbPacket packet) async {
    try {
      connection.socket.add(packet.data);
      await connection.socket.flush().timeout(const Duration(seconds: 15));
      if (_closed) return;
      await send(
        AdbPacket(AdbPacket.okay, id, remoteId),
        // ACK 在全局队列中仍占用本流额度；真正发送前释放，接纳对端的快速回包。
        beforeWrite: () => _writing = false,
      );
    } catch (_) {
      close();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    connection.close();
    if (_ack case final ack? when !ack.isCompleted) ack.complete();
    unawaited(send(AdbPacket(AdbPacket.clse, id, remoteId)).catchError((_) {}));
    onClose();
  }
}
