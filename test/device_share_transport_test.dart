import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:any_deck/core/device_share/adb/adb_packet.dart';
import 'package:any_deck/core/device_share/hosted_device_share.dart';
import 'package:any_deck/core/device_share/joined_device_share.dart';
import 'package:any_deck/core/device_share/share_socket_reader.dart';
import 'package:any_deck/core/device_share/share_tls_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_adb_service.dart';
import 'support/device_share_fixture.dart';

void main() {
  late ShareTlsIdentity identity;
  late ShareAdbFixture adb;
  late HostedDeviceShare host;
  final clients = <ShareClientFixture>[];

  setUpAll(() async {
    identity = await ShareTlsIdentity.generate();
  });
  setUp(() async {
    adb = ShareAdbFixture();
    await adb.start();
    host = await HostedDeviceShare.start(
      deviceId: 'usb-phone',
      backend: adb.backend,
      host: '127.0.0.1',
      identity: identity,
      onChanged: () {},
      bindAddress: InternetAddress.loopbackIPv4,
    );
  });
  tearDown(() async {
    for (final client in clients) {
      await client.close();
    }
    clients.clear();
    await host.close();
    await adb.close();
  });

  Future<ShareClientFixture> connect({String? token}) async {
    final client = await ShareClientFixture.connect(host, token: token);
    clients.add(client);
    return client;
  }

  test('TLS 指纹错误时不发送分享凭据', () async {
    final invite = replaceInvitation(host.invitation, fingerprint: '0' * 64);
    await expectLater(
      JoinedDeviceShare.connect(invite, FakeAdbService(), () {}),
      throwsA(isA<HandshakeException>()),
    );
    expect(host.connected, isFalse);
    expect(
      adb.requests.where((name) => name.startsWith('host:transport-id:')),
      isEmpty,
    );
  });

  test('无效令牌不能获取设备，合法令牌只允许一个接收端', () async {
    final invalid = await connect(token: 'wrong');
    expect((await invalid.auth())['ok'], isFalse);
    final first = await connect();
    expect((await first.auth())['ok'], isTrue);
    expect(host.connected, isTrue);
    final second = await connect();
    expect((await second.auth())['ok'], isFalse);
    expect(host.connected, isTrue);
  });

  test('握手标记共享来源并过滤不支持的流控能力', () async {
    final client = await connect();
    await client.auth();
    final packet = await client.handshake();
    expect(packet.command, AdbPacket.cnxn);
    final banner = utf8.decode(packet.data);
    expect(banner, contains('ro.product.name=anydeck_shared_device;'));
    expect(banner, contains('shell_v2'));
    expect(banner, isNot(contains('delayed_ack')));
  });

  test('Shell、文件和投屏服务每条流都绑定原 transport，二进制内容不变', () async {
    final bytes = Uint8List.fromList(List.generate(253, (i) => i));
    adb.onService = (_, socket, _) async {
      socket.add(bytes);
    };
    final client = await connect();
    await client.auth();
    await client.handshake();
    for (final (index, name) in [
      'shell:id',
      'sync:',
      'localabstract:scrcpy_test',
    ].indexed) {
      final remote = index + 1;
      await client.open(name, remote);
      final opened = await client.packet();
      expect(opened.command, AdbPacket.okay);
      final data = await client.packet();
      expect(data.command, AdbPacket.wrte);
      expect(data.data, bytes);
      await client.send(AdbPacket.okay, remote, opened.arg0);
      expect((await client.packet()).command, AdbPacket.clse);
    }
    expect(
      adb.requests.where((value) => value == 'host:transport-id:72').length,
      3,
    );
    expect(
      adb.requests.any((value) => value.contains('transport:other')),
      isFalse,
    );
  });

  test('不能透过 OPEN 杀死宿主 Server 或选择其他手机', () async {
    final client = await connect();
    await client.auth();
    await client.handshake();
    for (final request in ['host:kill', 'host:transport:other', 'tcpip:5555']) {
      await client.open(request);
      expect((await client.packet()).command, AdbPacket.clse);
    }
    expect(
      adb.requests.where((request) => request.startsWith('host:transport-id:')),
      isEmpty,
    );
  });

  test('多个设备服务同时返回时，每条流均能完整送达并正常结束', () async {
    final ready = Completer<void>();
    var services = 0;
    adb.onService = (name, socket, _) async {
      services++;
      await ready.future;
      socket.add(utf8.encode('$name result\n' * 8192));
    };
    final client = await connect();
    await client.auth();
    await client.handshake(payload: AdbPacket.maxPayload);
    for (var remoteId = 1; remoteId <= 8; remoteId++) {
      await client.open('shell:query$remoteId', remoteId);
      final opened = await client.packet();
      expect(opened.command, AdbPacket.okay);
    }
    expect(services, 8);
    ready.complete();
    final received = <int, String>{};
    final closed = <int>{};
    while (closed.length < 8) {
      final packet = await client.packet();
      if (packet.command == AdbPacket.wrte) {
        received.update(
          packet.arg1,
          (value) => value + utf8.decode(packet.data),
          ifAbsent: () => utf8.decode(packet.data),
        );
        await client.send(AdbPacket.okay, packet.arg1, packet.arg0);
      } else if (packet.command == AdbPacket.clse) {
        closed.add(packet.arg1);
      }
    }
    expect(received.keys.toSet(), {for (var id = 1; id <= 8; id++) id});
    for (var id = 1; id <= 8; id++) {
      expect(
        sha256.convert(utf8.encode(received[id]!)),
        sha256.convert(utf8.encode('shell:query$id result\n' * 8192)),
      );
    }
  });

  test('大流未 ACK 时暂停发送，确认后继续且保持数据顺序', () async {
    final content = Uint8List.fromList(List.generate(10000, (i) => i % 251));
    adb.onService = (_, socket, _) async {
      socket.add(content);
    };
    final client = await connect();
    await client.auth();
    await client.handshake();
    await client.open('sync:');
    final opened = await client.packet();
    final first = await client.packet();
    expect(first.data.length, lessThanOrEqualTo(4096));
    var arrived = false;
    final waiting = client.packet().then((packet) {
      arrived = true;
      return packet;
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(arrived, isFalse);
    await client.send(AdbPacket.okay, 1, opened.arg0);
    final output = BytesBuilder()..add(first.data);
    var next = await waiting;
    while (next.command == AdbPacket.wrte) {
      output.add(next.data);
      await client.send(AdbPacket.okay, 1, opened.arg0);
      next = await client.packet();
    }
    expect(next.command, AdbPacket.clse);
    expect(output.takeBytes(), content);
  });

  test('Reverse 的设备回连经 A_OPEN 到接收方，撤销只清理本会话规则', () async {
    adb.reversePorts['tcp:1111'] = 2222;
    final client = await connect();
    await client.auth();
    await client.handshake();
    await client.open('reverse:forward:tcp:43001;tcp:8081');
    final opened = await client.packet();
    final response = await client.packet();
    expect(ascii.decode(response.data), 'OKAY');
    await client.send(AdbPacket.okay, 1, opened.arg0);
    expect((await client.packet()).command, AdbPacket.clse);
    final callback = await Socket.connect(
      '127.0.0.1',
      adb.reversePorts['tcp:43001']!,
    );
    final callbackReader = ShareSocketReader(callback);
    final reverseOpen = await client.packet();
    expect(reverseOpen.command, AdbPacket.open);
    expect(utf8.decode(reverseOpen.data), 'tcp:8081\u0000');
    await client.send(AdbPacket.okay, 20, reverseOpen.arg0);
    callback.add([1, 2, 255]);
    await callback.flush();
    expect((await client.packet()).data, [1, 2, 255]);
    await client.send(AdbPacket.okay, 20, reverseOpen.arg0);
    await client.send(AdbPacket.wrte, 20, reverseOpen.arg0, [3, 4, 0]);
    expect(await callbackReader.read(3), [3, 4, 0]);
    await host.close();
    expect(adb.reversePorts, {'tcp:1111': 2222});
    callback.destroy();
    await callbackReader.cancel();
  });

  test('停止共享同时切断已有数据流并使原分享码失效', () async {
    final client = await connect();
    await client.auth();
    await client.handshake();
    final disconnected = client.reader.readChunk();
    await host.close();
    expect(await disconnected, isNull);
    await expectLater(
      Socket.connect('127.0.0.1', host.invitation.port),
      throwsA(isA<SocketException>()),
    );
  });

  test('停止与 Reverse 创建并发时，等待迟到的设备规则撤销后再完成', () async {
    adb.reverseGate = Completer<void>();
    final client = await connect();
    await client.auth();
    await client.handshake();
    await client.open('reverse:forward:tcp:43002;tcp:8082');
    for (
      var i = 0;
      i < 100 &&
          !adb.requests.any((value) => value.startsWith('reverse:forward:'));
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(
      adb.requests.any((value) => value.startsWith('reverse:forward:')),
      isTrue,
    );
    final stopped = host.close();
    adb.reverseGate!.complete();
    await stopped;
    expect(adb.reversePorts, isEmpty);
  });

  test('正在创建的 Reverse 也计入上限，不能并发绕过十六条规则限制', () async {
    adb.reverseGate = Completer<void>();
    final client = await connect();
    await client.auth();
    await client.handshake();
    for (var i = 0; i < 17; i++) {
      await client.open('reverse:forward:tcp:${44000 + i};tcp:8082', i + 1);
    }
    AdbPacket reply;
    do {
      reply = await client.packet();
    } while (reply.command != AdbPacket.wrte);
    expect(ascii.decode(reply.data), startsWith('FAIL'));
    for (
      var i = 0;
      i < 100 &&
          adb.requests.where((r) => r.startsWith('reverse:forward:')).length <
              16;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(
      adb.requests.where((r) => r.startsWith('reverse:forward:')),
      hasLength(16),
    );
    final stopped = host.close();
    adb.reverseGate!.complete();
    await stopped;
    expect(adb.reversePorts, isEmpty);
  });
}
