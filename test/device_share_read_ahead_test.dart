import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:any_deck/core/device_share/adb/adb_bridge_stream.dart';
import 'package:any_deck/core/device_share/adb/adb_packet.dart';
import 'package:any_deck/core/device_share/adb/shared_adb_backend.dart';
import 'package:any_deck/core/device_share/share_socket_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// 统计生产 Reader 实际取出的字节，验证满窗口后不再向源流请求数据。
class _CountingReader extends ShareSocketReader {
  _CountingReader(super.stream);
  int reads = 0, bytes = 0, cancellations = 0;

  @override
  Future<Uint8List?> readChunk([int limit = AdbPacket.maxPayload]) async {
    reads++;
    final data = await super.readChunk(limit);
    bytes += data?.length ?? 0;
    return data;
  }

  @override
  Future<void> cancel() {
    cancellations++;
    return super.cancel();
  }
}

/// Socket 生命周期由 Stream 持有；测试的输入通过独立可控 Stream 提供。
class _BackendSocket extends Fake implements Socket {
  bool destroyed = false;
  @override
  void destroy() => destroyed = true;
}

class _Bridge {
  _Bridge(int limit) {
    stream = AdbBridgeStream(
      id: 9,
      remoteId: 17,
      connection: SharedAdbConnection(socket, reader),
      payloadLimit: limit,
      send: (packet, {beforeWrite}) async {
        beforeWrite?.call();
        packets.add(packet);
      },
      onClose: () => closes++,
      onDiagnostic: diagnostics.add,
    );
  }

  final source = StreamController<Uint8List>();
  final socket = _BackendSocket();
  late final reader = _CountingReader(source.stream);
  late final AdbBridgeStream stream;
  final packets = <AdbPacket>[];
  final diagnostics = <String>[];
  bool completed = false;
  int closes = 0;
  Iterable<AdbPacket> get writes =>
      packets.where((packet) => packet.command == AdbPacket.wrte);

  void start({bool waitForOpen = false}) {
    unawaited(
      stream.pump(waitForOpen: waitForOpen).then((_) => completed = true),
    );
  }

  void add(List<int> bytes) => source.add(Uint8List.fromList(bytes));
  void ack() => stream.acknowledge(17);
  void eof() => unawaited(source.close());
  void close() {
    stream.close();
    if (!source.isClosed) eof();
  }
}

void main() {
  for (final limit in [4096, AdbPacket.maxPayload]) {
    test('窗口 $limit：首块即时发送，ACK 等待期间预取有界并合并，EOF 排空且 hash 不变', () {
      fakeAsync((clock) {
        final bridge = _Bridge(limit);
        final original = BytesBuilder();
        try {
          bridge.start();
          bridge.add([1, 2, 3]);
          original.add([1, 2, 3]);
          clock.flushMicrotasks();
          // 源端尚未提供下一块，首块不得等待凑满窗口或聚合 Timer。
          expect(bridge.writes.single.data, [1, 2, 3]);

          for (var value = 4; value <= 8; value++) {
            final chunk = List.filled(limit ~/ 4, value);
            original.add(chunk);
            bridge.add(chunk);
          }
          clock.flushMicrotasks();
          expect(bridge.reader.bytes, 3 + limit);
          expect(bridge.reader.reads, 5);
          expect(bridge.writes, hasLength(1));

          bridge.ack();
          clock.flushMicrotasks();
          expect(bridge.writes, hasLength(2));
          expect(bridge.writes.last.data.length, limit);
          expect(bridge.reader.bytes, 3 + limit + limit ~/ 4);
          bridge.eof();
          clock.flushMicrotasks();
          expect(bridge.packets.last.command, AdbPacket.wrte);

          bridge.ack();
          clock.flushMicrotasks();
          expect(bridge.writes, hasLength(3));
          expect(bridge.writes.last.data, List.filled(limit ~/ 4, 8));
          expect(bridge.packets.last.command, AdbPacket.wrte);
          expect(bridge.completed, isFalse);

          bridge.ack();
          clock.flushMicrotasks();
          expect(bridge.completed, isTrue);
          expect(bridge.packets.last.command, AdbPacket.clse);
          expect(
            bridge.writes.every((packet) => packet.data.length <= limit),
            isTrue,
          );
          final received = BytesBuilder();
          for (final packet in bridge.writes) {
            received.add(packet.data);
          }
          expect(
            sha256.convert(received.takeBytes()),
            sha256.convert(original.takeBytes()),
          );
          expect(bridge.diagnostics, isEmpty);
        } finally {
          bridge.close();
          clock.flushMicrotasks();
        }
      });
    });
  }

  test('读取等待时关闭会取消 Reader 并结束 pump，不等待源端继续输出', () {
    fakeAsync((clock) {
      final bridge = _Bridge(4096);
      bridge.start();
      clock.flushMicrotasks();
      expect(bridge.reader.reads, 1);
      bridge.close();
      clock.flushMicrotasks();
      expect(bridge.completed, isTrue);
      expect(bridge.reader.cancellations, 1);
      expect(bridge.socket.destroyed, isTrue);
      expect(bridge.closes, 1);
      expect(bridge.diagnostics, isEmpty);
    });
  });

  test('预读窗口已满且等待 ACK 时关闭会释放空间等待并停止预取', () {
    fakeAsync((clock) {
      final bridge = _Bridge(4096);
      try {
        bridge.start();
        bridge.add([1]);
        clock.flushMicrotasks();
        bridge.add(List.filled(4096, 2));
        bridge.add([3]);
        clock.flushMicrotasks();
        expect(bridge.reader.bytes, 4097);

        bridge.close();
        clock.flushMicrotasks();
        expect(bridge.completed, isTrue);
        expect(bridge.reader.bytes, 4097);
        expect(bridge.reader.cancellations, 1);
        expect(bridge.writes, hasLength(1));
        expect(bridge.packets.last.command, AdbPacket.clse);
        expect(clock.nonPeriodicTimerCount, 0);
      } finally {
        bridge.close();
        clock.flushMicrotasks();
      }
    });
  });

  test('预读异常先排空已读取前缀，随后按 device_read 诊断关闭且不泄露错误内容', () {
    fakeAsync((clock) {
      final bridge = _Bridge(4096);
      try {
        bridge.start();
        bridge.add([1]);
        clock.flushMicrotasks();
        bridge.add([2, 3]);
        bridge.add([4, 5]);
        bridge.source.addError(
          const SocketException('private fixture details'),
        );
        clock.flushMicrotasks();
        expect(bridge.reader.bytes, 5);
        expect(bridge.diagnostics, isEmpty);

        bridge.ack();
        clock.flushMicrotasks();
        expect(bridge.writes.last.data, [2, 3, 4, 5]);
        expect(bridge.completed, isFalse);
        bridge.ack();
        clock.flushMicrotasks();
        expect(bridge.completed, isTrue);
        expect(bridge.diagnostics, [
          'stream_failed stream_id=9 phase=device_read direction=from_device '
              'error_type=SocketException',
        ]);
        expect(bridge.packets.last.command, AdbPacket.clse);
      } finally {
        bridge.close();
        clock.flushMicrotasks();
      }
    });
  });

  test('Reverse 首次 OPEN 确认前不读取设备数据，确认后立即开始传输', () {
    fakeAsync((clock) {
      final bridge = _Bridge(4096);
      try {
        bridge.start(waitForOpen: true);
        bridge.add([1, 2]);
        clock.flushMicrotasks();
        expect(bridge.reader.reads, 0);
        expect(bridge.writes, isEmpty);
        bridge.ack();
        clock.flushMicrotasks();
        expect(bridge.writes.single.data, [1, 2]);
      } finally {
        bridge.close();
        clock.flushMicrotasks();
      }
    });
  });
}
