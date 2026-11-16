import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:any_deck/core/device_share/adb/adb_bridge_stream.dart';
import 'package:any_deck/core/device_share/adb/adb_packet.dart';
import 'package:any_deck/core/device_share/adb/shared_adb_backend.dart';
import 'package:any_deck/core/device_share/hosted_device_share.dart';
import 'package:any_deck/core/device_share/share_socket_reader.dart';
import 'package:any_deck/core/device_share/share_tls_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_share_fixture.dart';

/// 可控的后端消费速度只影响一条服务，不依赖操作系统 Socket 缓冲区大小。
class _ServiceSocket implements Socket {
  _ServiceSocket({this.gate});

  final Completer<void>? gate;
  final enteredFlush = Completer<void>();
  final input = StreamController<Uint8List>();
  final received = BytesBuilder();
  bool destroyed = false;

  @override
  void add(List<int> data) => received.add(data);

  @override
  Future<void> flush() async {
    if (!enteredFlush.isCompleted) enteredFlush.complete();
    await gate?.future;
  }

  @override
  void destroy() {
    if (destroyed) return;
    destroyed = true;
    if (gate case final pending? when !pending.isCompleted) pending.complete();
    unawaited(input.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 仅提供两条固定服务，视频最多两块数据，避免测试以无限缓冲模拟慢设备。
class _ControlledBackend extends SharedAdbBackend {
  _ControlledBackend()
    : super(transportId: '72', name: 'AnyDeck controlled phone');

  final writeGate = Completer<void>();
  late final blocked = _ServiceSocket(gate: writeGate);
  final normal = _ServiceSocket();
  final video = _ServiceSocket();

  @override
  Future<String> banner() async =>
      'device::ro.product.name=anydeck_shared_device;features=;\u0000';

  @override
  Future<SharedAdbConnection> open(String service) async {
    final socket = switch (service) {
      'shell:blocked-input' => blocked,
      'shell:input' => normal,
      _ => video,
    };
    if (identical(socket, video)) {
      socket.input.add(Uint8List.fromList(List.filled(8192, 42)));
    }
    return SharedAdbConnection(socket, ShareSocketReader(socket.input.stream));
  }

  void dispose() {
    blocked.destroy();
    normal.destroy();
    video.destroy();
  }
}

void main() {
  late ShareTlsIdentity identity;
  late _ControlledBackend backend;
  late HostedDeviceShare host;
  late ShareClientFixture client;

  setUpAll(() async {
    identity = await ShareTlsIdentity.generate();
  });
  setUp(() async {
    backend = _ControlledBackend();
    host = await HostedDeviceShare.start(
      deviceId: 'fixture-usb',
      backend: backend,
      host: '127.0.0.1',
      bindAddress: InternetAddress.loopbackIPv4,
      identity: identity,
      onChanged: () {},
    );
    client = await ShareClientFixture.connect(host);
    expect((await client.auth())['ok'], isTrue);
    await client.handshake();
  });
  tearDown(() async {
    backend.dispose();
    await client.close();
    await host.close();
  });

  Future<AdbPacket> startBlockedWrite() async {
    await client.open('shell:blocked-input', 2);
    final opened = await client.packet();
    expect(opened.command, AdbPacket.okay);
    await client.send(AdbPacket.wrte, 2, opened.arg0, [1, 2, 3]);
    await backend.blocked.enteredFlush.future.timeout(
      const Duration(seconds: 2),
    );
    return opened;
  }

  test('单条服务写入等待期间仍能处理另一条视频流的 ACK', () async {
    await client.open('localabstract:video', 1);
    final videoOpen = await client.packet();
    expect(videoOpen.command, AdbPacket.okay);
    final first = await client.packet();
    expect(first.command, AdbPacket.wrte);
    expect(first.data, List.filled(4096, 42));
    await startBlockedWrite();

    // 先确认后端已经在等待，再确认视频首块；此时不得依赖解除写入阻塞。
    await client.send(AdbPacket.okay, 1, videoOpen.arg0);
    final next = await client.packet().timeout(const Duration(seconds: 1));
    expect(backend.writeGate.isCompleted, isFalse);
    expect(next.command, AdbPacket.wrte);
    expect(next.arg1, 1);
    expect(next.data, List.filled(4096, 42));
  });

  test('慢写入期间对端关闭服务会立即回收后端且不补发 ACK', () async {
    final opened = await startBlockedWrite();
    await client.send(AdbPacket.clse, 2, opened.arg0);
    final closed = await client.packet().timeout(const Duration(seconds: 1));
    expect(closed.command, AdbPacket.clse);
    expect(closed.arg1, 2);
    expect(backend.blocked.destroyed, isTrue);
    // 后续服务仍可建立，且前面没有迟到的 OKAY。
    await client.open('shell:input', 3);
    final next = await client.packet();
    expect(next.command, AdbPacket.okay);
    expect(next.arg1, 3);
  });

  test('未确认的重复 WRTE 只关闭违规流且不继续积压输入', () async {
    final opened = await startBlockedWrite();
    await client.send(AdbPacket.wrte, 2, opened.arg0, [4, 5, 6]);
    final closed = await client.packet().timeout(const Duration(seconds: 1));
    expect(closed.command, AdbPacket.clse);
    expect(closed.arg1, 2);
    expect(backend.blocked.received.takeBytes(), [1, 2, 3]);
    expect(backend.blocked.destroyed, isTrue);
    await client.open('shell:input', 3);
    final next = await client.packet();
    expect(next.command, AdbPacket.okay);
    expect(next.arg1, 3);
  });

  test('同一流收到 ACK 后可按序继续写入所有 payload', () async {
    await client.open('shell:input', 1);
    final opened = await client.packet();
    expect(opened.command, AdbPacket.okay);
    for (var value = 1; value <= 3; value++) {
      await client.send(AdbPacket.wrte, 1, opened.arg0, [value]);
      final ack = await client.packet();
      expect(ack.command, AdbPacket.okay);
      expect(ack.arg1, 1);
    }
    expect(backend.normal.received.takeBytes(), [1, 2, 3]);
    expect(backend.normal.destroyed, isFalse);
  });

  test('ACK 尚在发送队列时重复输入不能绕过单流在途上限', () async {
    final socket = _ServiceSocket();
    final heldAck = Completer<void>();
    final queuedAck = Completer<void>();
    var closed = false;
    final stream = AdbBridgeStream(
      id: 1,
      remoteId: 2,
      connection: SharedAdbConnection(
        socket,
        ShareSocketReader(socket.input.stream),
      ),
      payloadLimit: 4096,
      send: (packet, {beforeWrite}) async {
        if (packet.command != AdbPacket.okay) return;
        queuedAck.complete();
        await heldAck.future;
        beforeWrite?.call();
      },
      onClose: () => closed = true,
    );
    try {
      stream.write(AdbPacket(AdbPacket.wrte, 2, 1, Uint8List.fromList([1])));
      await queuedAck.future.timeout(const Duration(seconds: 1));
      stream.write(AdbPacket(AdbPacket.wrte, 2, 1, Uint8List.fromList([2])));
      expect(closed, isTrue);
      expect(socket.received.takeBytes(), [1]);
    } finally {
      heldAck.complete();
      stream.close();
    }
  });

  test('ACK 已交给 Socket 时允许快速回包而不等待旧 flush 完成', () async {
    final socket = _ServiceSocket();
    final heldAck = Completer<void>();
    final secondAck = Completer<void>();
    late AdbBridgeStream stream;
    var acknowledgements = 0;
    var closed = false;
    stream = AdbBridgeStream(
      id: 1,
      remoteId: 2,
      connection: SharedAdbConnection(
        socket,
        ShareSocketReader(socket.input.stream),
      ),
      payloadLimit: 4096,
      send: (packet, {beforeWrite}) async {
        beforeWrite?.call();
        if (packet.command != AdbPacket.okay) return;
        if (++acknowledgements == 1) {
          stream.write(
            AdbPacket(AdbPacket.wrte, 2, 1, Uint8List.fromList([2])),
          );
          await heldAck.future;
        } else if (!secondAck.isCompleted) {
          secondAck.complete();
        }
      },
      onClose: () => closed = true,
    );
    try {
      stream.write(AdbPacket(AdbPacket.wrte, 2, 1, Uint8List.fromList([1])));
      await secondAck.future.timeout(const Duration(seconds: 1));
      expect(heldAck.isCompleted, isFalse);
      expect(socket.received.takeBytes(), [1, 2]);
      expect(closed, isFalse);
    } finally {
      heldAck.complete();
      stream.close();
    }
  });
}
