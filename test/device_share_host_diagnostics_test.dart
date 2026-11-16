import 'dart:async';

import 'package:any_deck/core/device_share/device_share_diagnostics.dart';
import 'package:any_deck/core/device_share/hosted_device_share.dart';
import 'package:any_deck/core/device_share/share_tls_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_share_fixture.dart';

/// 源端监听与接收连接是不同生命周期，日志必须区分且不能影响 Socket 回收。
void main() {
  late ShareAdbFixture backend;
  late ShareTlsIdentity identity;
  HostedDeviceShare? host;
  final diagnostics = <String>[];

  setUpAll(() async => identity = await ShareTlsIdentity.generate());
  setUp(() async {
    diagnostics.clear();
    backend = ShareAdbFixture();
    await backend.start();
  });
  tearDown(() async {
    await host?.close();
    host = null;
    await backend.close();
  });

  Future<HostedDeviceShare> start({
    Duration? lifetime,
    void Function(String)? report,
  }) async => host = await HostedDeviceShare.start(
    deviceId: 'fixture-usb',
    backend: backend.backend,
    host: '127.0.0.1',
    identity: identity,
    lifetime: lifetime,
    onChanged: () {},
    onDiagnostic: (event) {
      diagnostics.add(event);
      report?.call(event);
    },
  );

  test('接收方断开只结束 Peer，同一分享码仍可再次认证', () async {
    final ended = Completer<void>();
    final sharing = await start(
      report: (event) {
        if (event == 'host_peer_ended listener_open=true' &&
            !ended.isCompleted) {
          ended.complete();
        }
      },
    );
    final first = await ShareClientFixture.connect(sharing);
    expect((await first.auth())['ok'], isTrue);
    await first.handshake();
    await first.close();
    await ended.future.timeout(const Duration(seconds: 2));
    expect(sharing.closed, isFalse);
    expect(sharing.connected, isFalse);
    expect(diagnostics, isNot(contains(startsWith('host_stopped'))));

    final second = await ShareClientFixture.connect(sharing);
    try {
      expect((await second.auth())['ok'], isTrue);
      await second.handshake();
      expect(sharing.connected, isTrue);
    } finally {
      await second.close();
    }
  });

  test('真实到期计时器关闭监听并记录 expired 原因', () async {
    final stopped = Completer<void>();
    final sharing = await start(
      lifetime: const Duration(milliseconds: 50),
      report: (event) {
        if (event.startsWith('host_stopped') && !stopped.isCompleted) {
          stopped.complete();
        }
      },
    );
    await stopped.future.timeout(const Duration(seconds: 2));
    await sharing.close();
    expect(sharing.closed, isTrue);
    expect(diagnostics, [
      'host_stopped reason=expired receiver_connected=false',
    ]);
  });

  test('并发关闭只记录首个原因，不将主动停止改记为应用退出', () async {
    final sharing = await start();
    final requested = sharing.close();
    final exiting = sharing.close(reason: HostedShareStopReason.appExit);
    expect(identical(requested, exiting), isTrue);
    await Future.wait([requested, exiting]);
    expect(diagnostics, [
      'host_stopped reason=requested receiver_connected=false',
    ]);
  });

  test('诊断观察者抛异常仍能完成监听关闭', () async {
    final sharing = await start(
      report: (_) => throw StateError('observer gone'),
    );
    await sharing.close();
    expect(sharing.closed, isTrue);
    expect(diagnostics.single, startsWith('host_stopped reason=requested'));
  });
}
