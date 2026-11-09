import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/device_share/adb/adb_packet.dart';
import 'package:any_deck/core/device_share/hosted_device_share.dart';
import 'package:any_deck/core/device_share/share_tls_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_share_fixture.dart';

/// 验证等待设备服务建立时，Transport 仍能处理其他流的消息。
void main() {
  late ShareTlsIdentity identity;
  late ShareAdbFixture source;
  late HostedDeviceShare host;
  late ShareClientFixture client;
  late Completer<void> gate;
  late Completer<void> opening;

  setUpAll(() async {
    identity = await ShareTlsIdentity.generate();
  });
  setUp(() async {
    gate = Completer<void>();
    opening = Completer<void>();
    source = ShareAdbFixture();
    await source.start();
    source.beforeServiceReply = (name) async {
      if (name != 'shell:slow') return;
      if (!opening.isCompleted) opening.complete();
      await gate.future;
    };
    host = await HostedDeviceShare.start(
      deviceId: 'fixture-usb',
      backend: source.backend,
      host: '127.0.0.1',
      bindAddress: InternetAddress.loopbackIPv4,
      identity: identity,
      onChanged: () {},
    );
    client = await ShareClientFixture.connect(host);
    await client.auth();
    await client.handshake();
  });
  tearDown(() async {
    if (!gate.isCompleted) gate.complete();
    await client.close();
    await host.close();
    await source.close();
  });

  test('慢 OPEN 不阻塞已有大流的 ACK 与后续数据', () async {
    source.onService = (_, socket, _) async {
      socket.add(List.filled(8192, 42));
    };
    await client.open('shell:active');
    final active = await client.packet();
    expect(active.command, AdbPacket.okay);
    final first = await client.packet();
    expect(first.command, AdbPacket.wrte);
    expect(first.data.length, 4096);

    await client.open('shell:slow', 2);
    await opening.future.timeout(const Duration(seconds: 2));
    await client.send(AdbPacket.okay, 1, active.arg0);
    final next = await client.packet().timeout(const Duration(seconds: 1));
    expect(next.command, AdbPacket.wrte);
    expect(next.arg1, 1);
    expect(next.data, List.filled(4096, 42));
  });

  test('慢 OPEN 不阻塞其他设备信息查询建立与完成', () async {
    source.onService = (name, socket, _) async {
      socket.add(utf8.encode(name));
    };
    await client.open('shell:slow');
    await opening.future.timeout(const Duration(seconds: 2));
    await client.open('shell:id', 2);
    final ready = await client.packet().timeout(const Duration(seconds: 1));
    expect(ready.command, AdbPacket.okay);
    expect(ready.arg1, 2);
    final data = await client.packet();
    expect(utf8.decode(data.data), 'shell:id');
    await client.send(AdbPacket.okay, 2, ready.arg0);
    expect((await client.packet()).command, AdbPacket.clse);
    expect(gate.isCompleted, isFalse);
  });

  test('建立中的服务也受 64 条上限约束', () async {
    final allOpening = Completer<void>();
    var count = 0;
    source.beforeServiceReply = (_) async {
      if (++count == 64) allOpening.complete();
      await gate.future;
    };
    for (var id = 1; id <= 64; id++) {
      await client.open('shell:slow', id);
    }
    await allOpening.future.timeout(const Duration(seconds: 3));
    await client.open('shell:overflow', 65);
    final rejected = await client.packet();
    expect(rejected.command, AdbPacket.clse);
    expect(rejected.arg0, 0);
    expect(rejected.arg1, 65);
    expect(count, 64);
  });

  test('建立中不能重复使用同一远端 Stream ID', () async {
    await client.open('shell:slow');
    await opening.future.timeout(const Duration(seconds: 2));
    await client.open('shell:duplicate');
    expect((await client.packet()).command, AdbPacket.clse);
    expect(source.requests, isNot(contains('shell:duplicate')));
  });

  test('停止共享会回收尚在建立中的迟到后端连接', () async {
    final disconnected = Completer<void>();
    source.onService = (_, socket, reader) async {
      expect(await reader.readChunk(), isNull);
      disconnected.complete();
    };
    await client.open('shell:slow');
    await opening.future.timeout(const Duration(seconds: 2));
    final closing = host.close();
    gate.complete();
    await closing.timeout(const Duration(seconds: 2));
    await disconnected.future.timeout(const Duration(seconds: 2));
    expect(host.closed, isTrue);
  });
}
