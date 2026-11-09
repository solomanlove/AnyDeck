import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/device_share/device_share_discovery.dart';
import 'package:any_deck/core/device_share/device_share_invitation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 使用独立 UDP 端口验证地址重定位、凭据隔离和关闭回收。
void main() {
  late int port;
  late UdpDeviceShareDiscovery publisher, receiver;
  late DeviceShareInvitation invitation;
  setUp(() async {
    final reservation = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    port = reservation.port;
    reservation.close();
    publisher = UdpDeviceShareDiscovery(port: port);
    receiver = UdpDeviceShareDiscovery(port: port);
    invitation = DeviceShareInvitation(
      host: '127.0.0.1',
      port: 32000,
      fingerprint: 'a' * 64,
      token: DeviceShareInvitation.createToken(),
      name: 'test phone',
      resumable: true,
    );
  });
  tearDown(() async {
    await publisher.close();
    await receiver.close();
  });

  test('通过固定身份查找新的 TCP 端口，认证指纹和令牌不会被发现结果替换', () async {
    await publisher.publish([invitation.at('127.0.0.1', 53001)]);
    final found = await receiver.find(invitation);
    expect(found?.port, 53001);
    expect(found?.fingerprint, invitation.fingerprint);
    expect(found?.token, invitation.token);
  });

  test('停止发布后无法继续发现原共享', () async {
    await publisher.publish([invitation]);
    await publisher.publish([]);
    expect(await receiver.find(invitation), isNull);
  });

  test('查找报文不包含访问令牌，错误指纹和旧 nonce 的回复会被忽略', () async {
    final server = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      port,
    );
    addTearDown(server.close);
    server.writeEventsEnabled = false;
    final seen = <String>[];
    final subscription = server.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = server.receive()!;
      final text = utf8.decode(packet.data);
      seen.add(text);
      final request = jsonDecode(text) as Map;
      for (final (fingerprint, nonce, targetPort) in [
        ('b' * 64, request['nonce'], 1),
        (invitation.fingerprint, 'old', 2),
        (invitation.fingerprint, request['nonce'], 53002),
      ]) {
        server.send(
          utf8.encode(
            jsonEncode({
              'protocol': 'anydeck-device-share',
              'v': 1,
              'fp': fingerprint,
              'nonce': nonce,
              'port': targetPort,
            }),
          ),
          packet.address,
          packet.port,
        );
      }
    });
    addTearDown(subscription.cancel);
    final found = await receiver.find(invitation);
    expect(found?.port, 53002);
    expect(seen, isNotEmpty);
    expect(seen.any((message) => message.contains(invitation.token)), isFalse);
  });

  test('旧临时分享码不发送局域网发现请求', () async {
    final legacy = DeviceShareInvitation(
      host: invitation.host,
      port: invitation.port,
      fingerprint: invitation.fingerprint,
      token: invitation.token,
      name: invitation.name,
    );
    expect(await receiver.find(legacy), isNull);
  });

  test('关闭期间创建的监听也会回收，不留下 UDP 端口', () async {
    final opening = publisher.publish([invitation]);
    await publisher.close();
    await opening;
    final replacement = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: false,
    );
    replacement.close();
  });
}
