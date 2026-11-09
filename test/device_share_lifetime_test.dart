import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/device_share/hosted_device_share.dart';
import 'package:any_deck/core/device_share/share_tls_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_share_fixture.dart';

/// 验证实际 Socket 会话的时长、到期断开及永久模式的手动撤销。
void main() {
  late ShareTlsIdentity identity;
  late ShareAdbFixture source;
  HostedDeviceShare? host;
  ShareClientFixture? client;
  setUpAll(() async {
    identity = await ShareTlsIdentity.generate();
  });
  setUp(() async {
    source = ShareAdbFixture();
    await source.start();
  });
  tearDown(() async {
    await client?.close();
    client = null;
    await host?.close();
    host = null;
    await source.close();
  });

  for (final period in [
    const Duration(minutes: 30),
    const Duration(hours: 1),
  ]) {
    test('会话期限使用选定时长 $period', () async {
      final before = DateTime.now();
      host = await HostedDeviceShare.start(
        deviceId: 'phone',
        backend: source.backend,
        host: '127.0.0.1',
        identity: identity,
        lifetime: period,
        onChanged: () {},
      );
      final remaining = host!.invitation.expiresAt!.difference(before);
      expect(
        remaining.inMilliseconds,
        inInclusiveRange(period.inMilliseconds, period.inMilliseconds + 2000),
      );
    });
  }

  test('永久共享不创建到期时间，但仍可以手动撤销', () async {
    host = await HostedDeviceShare.start(
      deviceId: 'phone',
      backend: source.backend,
      host: '127.0.0.1',
      identity: identity,
      lifetime: null,
      onChanged: () {},
    );
    client = await ShareClientFixture.connect(host!);
    final response = await client!.auth();
    expect(response['expiresAt'], isNull);
    expect(host!.invitation.expiresAt, isNull);
    await host!.close();
    expect(host!.closed, isTrue);
  });

  test('到期会关闭等待入口和已经连接的 Transport', () async {
    final expired = Completer<void>();
    host = await HostedDeviceShare.start(
      deviceId: 'phone',
      backend: source.backend,
      host: '127.0.0.1',
      identity: identity,
      lifetime: const Duration(milliseconds: 300),
      onChanged: () {
        if (host?.closed == true && !expired.isCompleted) expired.complete();
      },
    );
    client = await ShareClientFixture.connect(host!);
    await client!.auth();
    await client!.handshake();
    await expired.future.timeout(const Duration(seconds: 3));
    expect(host!.closed, isTrue);
    await expectLater(client!.packet(), throwsA(isA<SocketException>()));
  });
}
