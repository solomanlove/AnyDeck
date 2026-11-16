import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:any_deck/core/device_share/adb/adb_bridge_stream.dart';
import 'package:any_deck/core/device_share/adb/adb_packet.dart';
import 'package:any_deck/core/device_share/adb/shared_adb_backend.dart';
import 'package:any_deck/core/device_share/adb/shared_adb_peer.dart';
import 'package:any_deck/core/device_share/share_socket_reader.dart';
import 'package:flutter_test/flutter_test.dart';

const _privatePayload = 'RAW_PAYLOAD_NEVER_LOGGED';

/// 只模拟写入和销毁，错误中带合成私密标记以验证日志边界。
class _DiagnosticSocket implements Socket {
  Object? failure;
  Completer<void>? flushGate;
  final flushing = Completer<void>();
  final added = Completer<void>();
  bool destroyed = false;

  @override
  void add(List<int> data) {
    if (!added.isCompleted) added.complete();
  }

  @override
  Future<void> flush() async {
    if (!flushing.isCompleted) flushing.complete();
    await flushGate?.future;
    if (failure case final error?) throw error;
  }

  @override
  void destroy() => destroyed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DiagnosticBackend extends SharedAdbBackend {
  _DiagnosticBackend({this.failure})
    : super(transportId: '7', name: 'AnyDeck fixture');
  final Object? failure;
  @override
  Future<String> banner() async {
    if (failure case final error?) throw error;
    return 'device::features=;\u0000';
  }
}

Uint8List _connect() => AdbPacket(AdbPacket.cnxn, 0x01000001, 4096).encode();

void main() {
  test('握手失败只收集方向与异常类型，并关闭 Transport', () async {
    final socket = _DiagnosticSocket();
    final diagnostics = <String>[];
    final peer = SharedAdbPeer(
      socket,
      ShareSocketReader(
        Stream.value(
          AdbPacket(
            AdbPacket.open,
            1,
            0,
            Uint8List.fromList(_privatePayload.codeUnits),
          ).encode(),
        ),
      ),
      _DiagnosticBackend(),
      onDiagnostic: diagnostics.add,
    );
    await expectLater(peer.run(), throwsA(isA<FormatException>()));
    expect(socket.destroyed, isTrue);
    expect(diagnostics, [
      'peer_transport_failed phase=handshake direction=from_receiver '
          'error_type=FormatException',
    ]);
    expect(diagnostics.join(), isNot(contains(_privatePayload)));
  });

  test('握手后接收异常归于 read，不泄露原始错误或 payload', () async {
    final socket = _DiagnosticSocket();
    final input = StreamController<Uint8List>()
      ..add(_connect())
      ..addError(StateError(_privatePayload));
    final diagnostics = <String>[];
    final peer = SharedAdbPeer(
      socket,
      ShareSocketReader(input.stream),
      _DiagnosticBackend(),
      onDiagnostic: diagnostics.add,
    );
    await expectLater(peer.run(), throwsA(isA<StateError>()));
    await input.close();
    expect(socket.destroyed, isTrue);
    expect(diagnostics, [
      'peer_transport_failed phase=read direction=from_receiver '
          'error_type=StateError',
    ]);
    expect(diagnostics.join(), isNot(contains(_privatePayload)));
  });

  test('出口写入失败只记录一次，不重复报告后续关闭的读错误', () async {
    final socket = _DiagnosticSocket()
      ..failure = const SocketException(_privatePayload);
    final diagnostics = <String>[];
    final peer = SharedAdbPeer(
      socket,
      ShareSocketReader(Stream.value(_connect())),
      _DiagnosticBackend(),
      onDiagnostic: diagnostics.add,
    );
    await expectLater(peer.run(), throwsA(isA<SocketException>()));
    expect(socket.destroyed, isTrue);
    expect(diagnostics, [
      'peer_transport_failed phase=write direction=to_receiver '
          'error_type=SocketException',
    ]);
    expect(diagnostics.join(), isNot(contains(_privatePayload)));
  });

  test('本机 ADB 的 banner 失败明确归于 local_adb', () async {
    final socket = _DiagnosticSocket();
    final diagnostics = <String>[];
    final peer = SharedAdbPeer(
      socket,
      ShareSocketReader(Stream.value(_connect())),
      _DiagnosticBackend(failure: const SocketException(_privatePayload)),
      onDiagnostic: diagnostics.add,
    );
    await expectLater(peer.run(), throwsA(isA<SocketException>()));
    expect(socket.destroyed, isTrue);
    expect(diagnostics, [
      'peer_transport_failed phase=backend_banner direction=local_adb '
          'error_type=SocketException',
    ]);
    expect(diagnostics.join(), isNot(contains(_privatePayload)));
  });

  test('日志回调抛出不改变原始失败，也不阻止 Socket 清理', () async {
    final socket = _DiagnosticSocket();
    final peer = SharedAdbPeer(
      socket,
      ShareSocketReader(Stream.value(AdbPacket(AdbPacket.open, 1, 0).encode())),
      _DiagnosticBackend(),
      onDiagnostic: (_) => throw StateError('observer failed'),
    );
    await expectLater(peer.run(), throwsA(isA<FormatException>()));
    expect(socket.destroyed, isTrue);
  });

  test('主动关闭 Transport 不产生接收失败诊断', () async {
    final socket = _DiagnosticSocket();
    final input = StreamController<Uint8List>()..add(_connect());
    final diagnostics = <String>[];
    final peer = SharedAdbPeer(
      socket,
      ShareSocketReader(input.stream),
      _DiagnosticBackend(),
      onDiagnostic: diagnostics.add,
    );
    final running = peer.run();
    await socket.added.future;
    await peer.close();
    await running;
    await input.close();
    expect(socket.destroyed, isTrue);
    expect(diagnostics, isEmpty);
  });

  test('设备服务读取失败只关闭本流并记录 from_device', () async {
    final socket = _DiagnosticSocket();
    final diagnostics = <String>[];
    var closed = false;
    final stream = AdbBridgeStream(
      id: 9,
      remoteId: 8,
      payloadLimit: 4096,
      connection: SharedAdbConnection(
        socket,
        ShareSocketReader(Stream<Uint8List>.error(StateError(_privatePayload))),
      ),
      send: (packet, {beforeWrite}) async => beforeWrite?.call(),
      onClose: () => closed = true,
      onDiagnostic: diagnostics.add,
    );
    await stream.pump();
    expect(closed, isTrue);
    expect(socket.destroyed, isTrue);
    expect(diagnostics, [
      'stream_failed stream_id=9 phase=device_read direction=from_device '
          'error_type=StateError',
    ]);
    expect(diagnostics.join(), isNot(contains(_privatePayload)));
  });

  test('设备服务写入失败记录 to_device，并保持本流回收', () async {
    final socket = _DiagnosticSocket()..failure = StateError(_privatePayload);
    final diagnostics = <String>[];
    final closed = Completer<void>();
    final stream = AdbBridgeStream(
      id: 9,
      remoteId: 8,
      payloadLimit: 4096,
      connection: SharedAdbConnection(
        socket,
        ShareSocketReader(const Stream<Uint8List>.empty()),
      ),
      send: (packet, {beforeWrite}) async => beforeWrite?.call(),
      onClose: closed.complete,
      onDiagnostic: diagnostics.add,
    );
    stream.write(AdbPacket(AdbPacket.wrte, 8, 9, Uint8List.fromList([1])));
    await closed.future;
    expect(socket.destroyed, isTrue);
    expect(diagnostics, [
      'stream_failed stream_id=9 phase=device_write direction=to_device '
          'error_type=StateError',
    ]);
    expect(diagnostics.join(), isNot(contains(_privatePayload)));
  });

  test('主动关闭服务后迟到的 flush 异常不误报故障', () async {
    final socket = _DiagnosticSocket()..flushGate = Completer<void>();
    final diagnostics = <String>[];
    final stream = AdbBridgeStream(
      id: 9,
      remoteId: 8,
      payloadLimit: 4096,
      connection: SharedAdbConnection(
        socket,
        ShareSocketReader(const Stream<Uint8List>.empty()),
      ),
      send: (packet, {beforeWrite}) async => beforeWrite?.call(),
      onClose: () {},
      onDiagnostic: diagnostics.add,
    );
    stream.write(AdbPacket(AdbPacket.wrte, 8, 9, Uint8List.fromList([1])));
    await socket.flushing.future;
    stream.close();
    socket.flushGate!.completeError(StateError(_privatePayload));
    await Future<void>.delayed(Duration.zero);
    expect(socket.destroyed, isTrue);
    expect(diagnostics, isEmpty);
  });

  testWidgets('等待 Reverse 首个 ACK 超时归于接收端 open_ack', (tester) async {
    final socket = _DiagnosticSocket();
    final diagnostics = <String>[];
    final stream = AdbBridgeStream(
      id: 9,
      remoteId: 0,
      payloadLimit: 4096,
      connection: SharedAdbConnection(
        socket,
        ShareSocketReader(const Stream<Uint8List>.empty()),
      ),
      send: (packet, {beforeWrite}) async => beforeWrite?.call(),
      onClose: () {},
      onDiagnostic: diagnostics.add,
    );
    final pumping = stream.pump(waitForOpen: true);
    await tester.pump(const Duration(seconds: 16));
    await pumping;
    expect(socket.destroyed, isTrue);
    expect(diagnostics, [
      'stream_failed stream_id=9 phase=open_ack direction=from_receiver '
          'error_type=TimeoutException',
    ]);
  });

  testWidgets('等待数据 ACK 超时归于接收端 data_ack', (tester) async {
    final socket = _DiagnosticSocket();
    final diagnostics = <String>[];
    final stream = AdbBridgeStream(
      id: 9,
      remoteId: 8,
      payloadLimit: 4096,
      connection: SharedAdbConnection(
        socket,
        ShareSocketReader(Stream.value(Uint8List.fromList([1]))),
      ),
      send: (packet, {beforeWrite}) async => beforeWrite?.call(),
      onClose: () {},
      onDiagnostic: diagnostics.add,
    );
    final pumping = stream.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    await pumping;
    expect(socket.destroyed, isTrue);
    expect(diagnostics, [
      'stream_failed stream_id=9 phase=data_ack direction=from_receiver '
          'error_type=TimeoutException',
    ]);
  });

  test('数据发送失败归于出口 transport_write', () async {
    final socket = _DiagnosticSocket();
    final diagnostics = <String>[];
    final stream = AdbBridgeStream(
      id: 9,
      remoteId: 8,
      payloadLimit: 4096,
      connection: SharedAdbConnection(
        socket,
        ShareSocketReader(Stream.value(Uint8List.fromList([1]))),
      ),
      send: (packet, {beforeWrite}) async {
        if (packet.command == AdbPacket.wrte) {
          throw StateError(_privatePayload);
        }
      },
      onClose: () {},
      onDiagnostic: diagnostics.add,
    );
    await stream.pump();
    expect(socket.destroyed, isTrue);
    expect(diagnostics, [
      'stream_failed stream_id=9 phase=transport_write direction=to_receiver '
          'error_type=StateError',
    ]);
  });

  test('设备写入后的确认发送失败归于出口 ack_write', () async {
    final socket = _DiagnosticSocket();
    final diagnostics = <String>[];
    final closed = Completer<void>();
    final stream = AdbBridgeStream(
      id: 9,
      remoteId: 8,
      payloadLimit: 4096,
      connection: SharedAdbConnection(
        socket,
        ShareSocketReader(const Stream<Uint8List>.empty()),
      ),
      send: (packet, {beforeWrite}) async {
        if (packet.command == AdbPacket.okay) {
          throw StateError(_privatePayload);
        }
      },
      onClose: closed.complete,
      onDiagnostic: diagnostics.add,
    );
    stream.write(AdbPacket(AdbPacket.wrte, 8, 9, Uint8List.fromList([1])));
    await closed.future;
    expect(socket.destroyed, isTrue);
    expect(diagnostics, [
      'stream_failed stream_id=9 phase=ack_write direction=to_receiver '
          'error_type=StateError',
    ]);
  });
}
