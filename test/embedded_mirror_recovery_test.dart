import 'dart:async';

import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/embedded_scrcpy_service.dart';
import 'package:any_deck/core/scrcpy/mirror_stream_health.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mirror_transport_fakes.dart';

/// 通过假 server 和原生健康快照验证重建链路，不启动 App 或连接手机。
void main() {
  const tcp = '192.168.1.8:5555';
  late TransportMirrors mirrors;
  late ProviderContainer container;
  setUp(() {
    mirrors = TransportMirrors();
    container = ProviderContainer(
      overrides: [
        adbServiceProvider.overrideWithValue(TransportAdb()),
        embeddedScrcpyServiceProvider.overrideWithValue(mirrors),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> congest(WidgetTester tester) async {
    mirrors.health[tcp] = const MirrorStreamHealth(videoLagMs: 500);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump();
  }

  testWidgets('无线降级重建保留 App 参数及静音，旧退出回调不触发换线', (tester) async {
    final notifier = container.read(activeEmbeddedMirrorProvider(tcp).notifier);
    await notifier.toggleMirroring(
      newDisplay: '1080x1920',
      startApp: 'example.app',
      initiallyMuted: true,
    );
    await congest(tester);
    expect(mirrors.starts, hasLength(2));
    expect(mirrors.starts.last, (
      id: tcp,
      display: '1080x1920',
      app: 'example.app',
      muted: true,
    ));
    final quality = mirrors.requestedQualities.last!;
    expect((quality.maxSize, quality.bitrate), (1080, 4000000));
    expect(mirrors.events, [
      'start:$tcp',
      'stop:$tcp',
      'stopped:$tcp',
      'start:$tcp',
    ]);
    expect(container.read(mirrorDisconnectedProvider(tcp)), 0);
    await tester.pump(const Duration(seconds: 5));
    expect(mirrors.starts, hasLength(2));
    await notifier.forceStop();
  });

  testWidgets('恢复清理期间关闭窗口，不再启动旧通道', (tester) async {
    final notifier = container.read(activeEmbeddedMirrorProvider(tcp).notifier);
    await notifier.toggleMirroring();
    final gate = Completer<void>();
    mirrors.stopGates[tcp] = gate;
    await congest(tester);
    final closing = notifier.forceStop();
    gate.complete();
    await closing;
    await tester.pump();
    expect(mirrors.starts, hasLength(1));
    expect(mirrors.isActive(tcp), isFalse);
    expect(container.read(mirrorDisconnectedProvider(tcp)), 0);
  });

  testWidgets('重建期间焦点变为静音，使用最新状态启动', (tester) async {
    final notifier = container.read(activeEmbeddedMirrorProvider(tcp).notifier);
    await notifier.toggleMirroring(initiallyMuted: false);
    final gate = Completer<void>();
    mirrors.stopGates[tcp] = gate;
    await congest(tester);
    mirrors.setMuted(tcp, true);
    gate.complete();
    await tester.pump();
    expect(mirrors.starts.last.muted, isTrue);
    await notifier.forceStop();
  });

  testWidgets('USB 音频流异常可重建，纯视频积压不降级', (tester) async {
    const usb = 'phone';
    final notifier = container.read(activeEmbeddedMirrorProvider(usb).notifier);
    await notifier.toggleMirroring();
    mirrors.health[usb] = const MirrorStreamHealth(videoLagMs: 1000);
    await tester.pump(const Duration(seconds: 4));
    expect(mirrors.starts, hasLength(1));
    mirrors.health[usb] = const MirrorStreamHealth(audioFailed: true);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(mirrors.starts, hasLength(2));
    expect(mirrors.requestedQualities.last?.bitrate, 8000000);
    await notifier.forceStop();
  });

  testWidgets('降级启动失败通知现有选路恢复，手动刷新重置画质', (tester) async {
    final notifier = container.read(activeEmbeddedMirrorProvider(tcp).notifier);
    await notifier.toggleMirroring();
    mirrors.failStart.add(tcp);
    await congest(tester);
    expect(container.read(mirrorDisconnectedProvider(tcp)), 1);
    expect(container.read(activeEmbeddedMirrorProvider(tcp)), isNull);
    mirrors.failStart.clear();
    await notifier.restartMirroring();
    expect(mirrors.requestedQualities.last, isNull);
    await notifier.forceStop();
  });
}
