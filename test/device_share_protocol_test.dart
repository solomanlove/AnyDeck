import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/adb/wireless/adb_wireless_state.dart';
import 'package:any_deck/core/device_share/adb/adb_packet.dart';
import 'package:any_deck/core/device_share/adb/shared_adb_peer.dart';
import 'package:any_deck/core/device_share/device_share_invitation.dart';
import 'package:any_deck/core/device_share/share_socket_reader.dart';
import 'package:any_deck/core/providers/modules/registered_device_model.dart';
import 'package:any_deck/core/scrcpy/mirror_transport_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AnyDeck 分享码保留中文名称并校验完整凭据', () {
    final invite = DeviceShareInvitation(
      host: '192.168.0.2',
      port: 43210,
      fingerprint: 'a' * 64,
      token: DeviceShareInvitation.createToken(),
      name: '测试 手机',
    );
    final parsed = DeviceShareInvitation.parse(invite.encode());
    expect(parsed.host, invite.host);
    expect(parsed.token, invite.token);
    expect(parsed.fingerprint, invite.fingerprint);
    expect(parsed.name, invite.name);
    expect(DeviceShareInvitation.createToken(), isNot(invite.token));
  });

  for (final invalid in [
    'https://192.168.0.2:33',
    'anydeck-share://user@192.168.0.2:33',
    'anydeck-share://evil.example:33',
    'anydeck-share://224.0.0.1:33',
    'anydeck-share://127.0.0.1:0',
    'anydeck-share://127.0.0.1:65536',
    'anydeck-share://127.0.0.1:33?key=secret',
  ]) {
    test('拒绝非预期分享地址 $invalid', () {
      expect(() => DeviceShareInvitation.parse(invalid), throwsFormatException);
    });
  }

  test('拒绝重复令牌参数、路径和截断凭据', () {
    final code = DeviceShareInvitation(
      host: '127.0.0.1',
      port: 33,
      fingerprint: 'a' * 64,
      token: 'x' * 43,
      name: 'test',
    ).encode();
    for (final value in [
      '$code&key=${'b' * 43}',
      '$code#fragment',
      code.replaceFirst(':33?', ':33/path?'),
      code.substring(0, 20),
    ]) {
      expect(() => DeviceShareInvitation.parse(value), throwsFormatException);
    }
  });

  test('碎片与粘包读取不丢失握手后的 ADB 字节', () async {
    final input = StreamController<Uint8List>();
    final reader = ShareSocketReader(input.stream);
    final json = utf8.encode('{"ok":true}');
    final bytes = Uint8List(4 + json.length + 3);
    ByteData.sublistView(bytes).setUint32(0, json.length);
    bytes.setRange(4, 4 + json.length, json);
    bytes.setRange(4 + json.length, bytes.length, [0, 255, 32]);
    for (final byte in bytes) {
      input.add(Uint8List.fromList([byte]));
    }
    unawaited(input.close());
    expect(await reader.readMessage(), {'ok': true});
    expect(await reader.read(3), [0, 255, 32]);
    expect(await reader.readChunk(), isNull);
    await reader.cancel();
  });

  test('握手控制消息和 Transport payload 在分配前限长', () async {
    final size = ByteData(4)..setUint32(0, 0xffffffff);
    final reader = ShareSocketReader(Stream.value(size.buffer.asUint8List()));
    await expectLater(reader.readMessage(), throwsFormatException);
    await reader.cancel();
    final header = ByteData(24)
      ..setUint32(0, AdbPacket.wrte, Endian.little)
      ..setUint32(12, AdbPacket.maxPayload + 1, Endian.little)
      ..setUint32(20, AdbPacket.wrte ^ 0xffffffff, Endian.little);
    final adb = ShareSocketReader(Stream.value(header.buffer.asUint8List()));
    await expectLater(AdbPacket.read(adb), throwsFormatException);
    await adb.cancel();
  });

  test('拒绝坏 magic、坏 checksum 与截断报文', () async {
    final packet = AdbPacket(
      AdbPacket.wrte,
      1,
      2,
      Uint8List.fromList([1, 2, 3]),
    ).encode();
    for (final bytes in [
      Uint8List.fromList(packet)..[20] ^= 1,
      Uint8List.fromList(packet)..[24] = 99,
      packet.sublist(0, 20),
    ]) {
      final reader = ShareSocketReader(Stream.value(bytes));
      await expectLater(AdbPacket.read(reader), throwsA(anything));
      await reader.cancel();
    }
  });

  test('设备服务允许二进制转发，宿主和重新选设备请求一律拒绝', () {
    for (final name in [
      'shell:id',
      'shell,v2,raw:id',
      'sync:',
      'localabstract:scrcpy_abc',
      'jdwp:123',
      'abb_exec:package\u0000install\u0000-S\u000010',
      'tcp:9222',
    ]) {
      expect(SharedAdbPeer.allowsService(name), isTrue, reason: name);
    }
    for (final name in [
      'host:kill',
      'host:transport:other-device',
      'host-serial:other:shell:id',
      'tcpip:5555',
      'shell:id\u0000host:kill',
      'x' * 4097,
    ]) {
      expect(SharedAdbPeer.allowsService(name), isFalse, reason: name);
    }
  });

  test('共享来源按 Bridge 标记识别，回环端口不被当作手机 TLS 无线调试', () {
    const discovered = DiscoveredDevice(
      id: '127.0.0.1:32112',
      status: 'device',
      product: 'anydeck_shared_device',
    );
    const device = RegisteredDevice(
      id: '127.0.0.1:32112',
      status: 'device',
      product: 'anydeck_shared_device',
      isOnline: true,
    );
    expect(discovered.isShared, isTrue);
    expect(device.isShared, isTrue);
    expect(device.hasTcpConnection, isTrue);
    expect(device.hasWifiDebuggingConnection, isFalse);
    expect(isWirelessTlsId(discovered.id), isFalse);
    expect(
      MirrorTransportType.fromDeviceId(discovered.id),
      MirrorTransportType.tcp,
    );
    expect(isWirelessTlsId('192.168.0.3:32112'), isTrue);
  });
}
