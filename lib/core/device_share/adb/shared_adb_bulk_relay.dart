import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../share_socket_reader.dart';
import 'adb_packet.dart';

/// 接收端为批量上传提前确认本地输入，并将积压合并为一块远端 WRTE。
/// 远端继续使用 Legacy ADB；仅四条批量流可占用各自至多两块 payload。
class SharedAdbBulkRelay {
  SharedAdbBulkRelay({
    required this.localSocket,
    required this.localReader,
    required this.remoteSocket,
    required this.remoteReader,
    this.onDiagnostic,
  });

  final Socket localSocket, remoteSocket;
  final ShareSocketReader localReader, remoteReader;
  final void Function(String message)? onDiagnostic;
  final _bulk = <int, _BulkUpload>{};
  final _failed = Completer<void>();
  Future<void> _localTail = Future<void>.value();
  Future<void> _remoteTail = Future<void>.value();
  int _payloadLimit = 4096;
  bool _closed = false;

  Future<void> run() async {
    try {
      await Future.any([
        _pump(localReader, _fromLocal, 'local'),
        _pump(remoteReader, _fromRemote, 'remote'),
        _failed.future,
      ]);
    } finally {
      close();
    }
  }

  Future<void> _pump(
    ShareSocketReader reader,
    Future<void> Function(AdbPacket) handle,
    String direction,
  ) async {
    try {
      while (!_closed) {
        await handle(await AdbPacket.read(reader));
      }
    } catch (error) {
      if (!_closed) {
        try {
          onDiagnostic?.call(
            'relay_input_closed direction=$direction error_type=${error.runtimeType}',
          );
        } catch (_) {
          // 诊断回调不能改变 Socket 的关闭结果。
        }
      }
      rethrow;
    }
  }

  /// 本地提前 ACK 与远端回包共享写队列，避免 Socket.flush 并发绑定。
  Future<void> _write(
    AdbPacket packet, {
    required bool toLocal,
    bool Function()? isCurrent,
    void Function()? beforeWrite,
  }) {
    final tail = toLocal ? _localTail : _remoteTail;
    final sent = tail.then((_) async {
      if (_closed || isCurrent?.call() == false) {
        return;
      }
      final socket = toLocal ? localSocket : remoteSocket;
      beforeWrite?.call();
      socket.add(packet.encode());
      await socket.flush().timeout(const Duration(seconds: 15));
    });
    final guarded = sent.catchError((Object error, StackTrace stack) {
      if (!_failed.isCompleted) _failed.completeError(error, stack);
    });
    if (toLocal) {
      _localTail = guarded;
    } else {
      _remoteTail = guarded;
    }
    return sent;
  }

  bool _isBulkOpen(AdbPacket packet) {
    if (packet.arg0 == 0 || packet.arg1 != 0 || packet.data.isEmpty) {
      return false;
    }
    final name = utf8.decode(packet.data, allowMalformed: true);
    return name == 'sync:\u0000' ||
        name.startsWith('abb:') ||
        name.startsWith('abb_exec:');
  }

  Future<void> _fromLocal(AdbPacket packet) async {
    if (packet.command == AdbPacket.open &&
        _bulk.length < 4 &&
        !_bulk.containsKey(packet.arg0) &&
        _isBulkOpen(packet)) {
      _bulk[packet.arg0] = _BulkUpload(packet.arg0);
    }
    final upload = _bulk[packet.arg0];
    if (upload != null &&
        upload.remoteId != null &&
        upload.remoteId == packet.arg1) {
      if (packet.command == AdbPacket.wrte) {
        // 每次本地 ACK 只允许下一块，限制恶意或不合规发送者的缓存占用。
        if (upload.localAckPending || upload.closePending != null) {
          await _reject(upload);
          return;
        }
        if (packet.data.length > _payloadLimit) {
          await _reject(upload);
          return;
        }
        upload.localAckPending = true;
        // 空 WRTE 不携带服务字节，直接确认，避免零字节包绕过字节窗口堆积队列。
        if (packet.data.isNotEmpty) {
          upload.queue.add(packet.data);
        }
        upload.queuedBytes += packet.data.length;
        _launch(_advance(upload));
        return;
      }
      if (packet.command == AdbPacket.clse) {
        // 已向本机确认的字节必须先送达，不能让 CLSE 越过合并队列。
        upload.closePending = packet;
        _launch(_advance(upload));
        return;
      }
    }
    await _write(packet, toLocal: false);
  }

  Future<void> _fromRemote(AdbPacket packet) async {
    if (packet.command == AdbPacket.cnxn) {
      _payloadLimit = packet.arg1.clamp(4096, AdbPacket.maxPayload);
    }
    final upload = _bulk[packet.arg1];
    if (upload != null) {
      if (packet.command == AdbPacket.clse) {
        if (upload.remoteId == packet.arg0 ||
            upload.remoteId == null && packet.arg0 == 0) {
          _remove(upload);
        } else {
          return;
        }
      } else if (packet.command == AdbPacket.okay) {
        if (upload.remoteId == null && packet.arg0 != 0) {
          upload.remoteId = packet.arg0;
        } else if (upload.remoteId == packet.arg0 && upload.inFlight) {
          // 这一块已被代理提前确认，不能再向本地重复发布远端 ACK。
          upload.ackTimer?.cancel();
          upload.inFlight = false;
          upload.inFlightBytes = 0;
          _launch(_advance(upload));
          return;
        } else {
          // 重复或错误 ID 的 ACK 不能给已提前确认的本机发送者凭空增加额度。
          return;
        }
      }
    }
    await _write(packet, toLocal: true);
  }

  void _launch(Future<void> operation) {
    unawaited(
      operation.catchError((Object error, StackTrace stack) {
        if (!_failed.isCompleted) _failed.completeError(error, stack);
      }),
    );
  }

  Future<void> _advance(_BulkUpload upload) async {
    if (!_isCurrent(upload) || upload.closingSent) return;
    if (!upload.inFlight && upload.queue.isNotEmpty) {
      final data = upload.take(_payloadLimit);
      upload.inFlight = true;
      upload.inFlightBytes = data.length;
      upload.ackTimer = Timer(const Duration(seconds: 30), () {
        unawaited(
          _reject(upload).catchError((Object error, StackTrace stack) {
            if (!_failed.isCompleted) _failed.completeError(error, stack);
          }),
        );
      });
      await _write(
        AdbPacket(AdbPacket.wrte, upload.localId, upload.remoteId!, data),
        toLocal: false,
        isCurrent: () => _isCurrent(upload) && !upload.closingSent,
      );
    }
    if (!_isCurrent(upload)) return;
    if (upload.closePending != null) {
      if (!upload.inFlight && upload.queue.isEmpty) {
        final close = upload.closePending!;
        upload.closingSent = true;
        await _write(
          close,
          toLocal: false,
          isCurrent: () => _isCurrent(upload),
        );
      }
      return;
    }
    if (upload.localAckPending &&
        !upload.localAckQueued &&
        upload.inFlightBytes + upload.queuedBytes < _payloadLimit) {
      upload.localAckQueued = true;
      await _write(
        AdbPacket(AdbPacket.okay, upload.remoteId!, upload.localId),
        toLocal: true,
        isCurrent: () => _isCurrent(upload) && upload.closePending == null,
        beforeWrite: () {
          upload.localAckQueued = false;
          upload.localAckPending = false;
        },
      );
    }
  }

  bool _isCurrent(_BulkUpload upload) =>
      !_closed && identical(_bulk[upload.localId], upload);

  Future<void> _reject(_BulkUpload upload) async {
    if (!identical(_bulk[upload.localId], upload)) return;
    _remove(upload);
    final remoteId = upload.remoteId;
    if (remoteId == null) return;
    await Future.wait([
      _write(
        AdbPacket(AdbPacket.clse, upload.localId, remoteId),
        toLocal: false,
      ),
      _write(
        AdbPacket(AdbPacket.clse, remoteId, upload.localId),
        toLocal: true,
      ),
    ]);
  }

  void _remove(_BulkUpload upload) {
    _bulk.remove(upload.localId);
    upload.ackTimer?.cancel();
    upload.queue.clear();
    upload.queuedBytes = 0;
  }

  /// Socket 由 JoinedDeviceShare 持有；关闭中仅取消本层窗口、计时器与缓存。
  void close() {
    _closed = true;
    for (final upload in _bulk.values.toList()) {
      _remove(upload);
    }
  }
}

/// 每流独立维护一块在途数据和有界待发队列，不缓存整个 APK。
class _BulkUpload {
  _BulkUpload(this.localId);
  final int localId;
  int? remoteId;
  final queue = Queue<Uint8List>();
  int queuedBytes = 0, inFlightBytes = 0;
  bool inFlight = false, localAckPending = false, closingSent = false;
  bool localAckQueued = false;
  Timer? ackTimer;
  AdbPacket? closePending;

  Uint8List take(int limit) {
    final bytes = BytesBuilder(copy: false);
    var remaining = limit;
    do {
      final chunk = queue.removeFirst();
      final count = chunk.length.clamp(0, remaining);
      bytes.add(Uint8List.sublistView(chunk, 0, count));
      if (count < chunk.length) {
        queue.addFirst(Uint8List.sublistView(chunk, count));
      }
      queuedBytes -= count;
      remaining -= count;
    } while (queue.isNotEmpty && remaining > 0);
    return bytes.takeBytes();
  }
}
