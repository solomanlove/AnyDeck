import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/window/mirror/android_mirror_transport_host.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/embedded_scrcpy_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mirror_transport_fakes.dart';

const _tcp = '192.168.1.8:5555';
const _tls = 'adb-phone-xyz._adb-tls-connect._tcp';

/// 模拟真实窗口内容：每次绑定新路由后启动会话，销毁时主动停止旧路由。
class _MirrorContent extends ConsumerStatefulWidget {
  const _MirrorContent(this.deviceId);
  final String deviceId;
  @override
  ConsumerState<_MirrorContent> createState() => _MirrorContentState();
}

class _MirrorContentState extends ConsumerState<_MirrorContent> {
  late final ActiveEmbeddedMirrorNotifier _notifier;
  @override
  void initState() {
    super.initState();
    _notifier = ref.read(activeEmbeddedMirrorProvider(widget.deviceId).notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await _notifier.toggleMirroring(
              newDisplay: '1080x1920',
              startApp: 'example.app',
              initiallyMuted: true,
            );
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    unawaited(_notifier.forceStop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texture = ref.watch(activeEmbeddedMirrorProvider(widget.deviceId));
    return Text('route:${widget.deviceId},texture:$texture');
  }
}

Future<void> _pumpHost(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: AndroidMirrorTransportHost(
          deviceId: 'phone',
          builder: (_, id) => _MirrorContent(id),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late TransportAdb adb;
  late TransportMirrors mirrors;
  late ProviderContainer container;
  setUp(() {
    adb = TransportAdb()
      ..devices = '$_tcp device\n$_tls device'
      ..serials.addAll({_tcp: 'phone', _tls: 'phone'});
    mirrors = TransportMirrors();
    container = ProviderContainer(
      overrides: [
        adbServiceProvider.overrideWithValue(adb),
        embeddedScrcpyServiceProvider.overrideWithValue(mirrors),
      ],
    );
  });
  tearDown(() => container.dispose());

  test('异常退出立即通知，旧会话清理完成前 forceStop 不提前返回', () async {
    final notifier = container.read(
      activeEmbeddedMirrorProvider('phone').notifier,
    );
    await notifier.toggleMirroring();
    final gate = Completer<void>();
    mirrors.stopGates['phone'] = gate;
    mirrors.processes['phone']!.ended.complete(1);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(mirrorDisconnectedProvider('phone')), 1);
    expect(container.read(activeEmbeddedMirrorProvider('phone')), isNull);
    var stopped = false;
    final stop = notifier.forceStop().then((_) => stopped = true);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    gate.complete();
    await stop;
    expect(stopped, isTrue);
  });

  test('主动停止不发断线事件，退出回调不能清掉新会话', () async {
    final notifier = container.read(
      activeEmbeddedMirrorProvider('phone').notifier,
    );
    await notifier.toggleMirroring();
    await notifier.forceStop();
    await notifier.toggleMirroring();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(mirrorDisconnectedProvider('phone')), 0);
    expect(container.read(activeEmbeddedMirrorProvider('phone')), 2);
  });

  test('并发启动只建立一次，启动未完成时停止会清理迟到的会话', () async {
    mirrors.startGate = Completer<void>();
    final notifier = container.read(
      activeEmbeddedMirrorProvider('phone').notifier,
    );
    final first = notifier.toggleMirroring();
    final second = notifier.toggleMirroring();
    final stop = notifier.forceStop();
    mirrors.startGate!.complete();
    await Future.wait([first, second, stop]);
    expect(mirrors.starts, hasLength(1));
    expect(mirrors.isActive('phone'), isFalse);
    expect(container.read(mirrorDisconnectedProvider('phone')), 0);
  });

  test('Provider 销毁后启动才返回时也释放会话', () async {
    mirrors.startGate = Completer<void>();
    final pending = container
        .read(activeEmbeddedMirrorProvider('phone').notifier)
        .toggleMirroring();
    container.dispose();
    mirrors.startGate!.complete();
    await pending;
    expect(mirrors.isActive('phone'), isFalse);
  });

  testWidgets('USB 断开后在原宿主内用 TCP 恢复，画面及启动参数统一换线', (tester) async {
    await _pumpHost(tester, container);
    mirrors.processes['phone']!.ended.complete(1);
    await tester.pumpAndSettle();
    expect(mirrors.starts.map((start) => start.id), ['phone', _tcp]);
    expect(find.text('route:$_tcp,texture:2'), findsOneWidget);
    expect(mirrors.starts.last.display, '1080x1920');
    expect(mirrors.starts.last.app, 'example.app');
    expect(mirrors.starts.last.muted, isTrue);
    expect(
      mirrors.events.indexOf('stopped:phone'),
      lessThan(mirrors.events.indexOf('start:$_tcp')),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('重复断线通知只查询一次，查询立即进行但等待旧资源释放才启动', (tester) async {
    await _pumpHost(tester, container);
    final gate = Completer<void>();
    mirrors.stopGates['phone'] = gate;
    mirrors.processes['phone']!.ended.complete(1);
    await tester.pump();
    container.read(mirrorDisconnectedProvider('phone').notifier).disconnected();
    await tester.pump();
    expect(adb.calls.where((args) => args.first == 'devices'), hasLength(1));
    expect(mirrors.starts, hasLength(1));
    gate.complete();
    await tester.pumpAndSettle();
    expect(mirrors.starts.map((start) => start.id), ['phone', _tcp]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('新通道启动也失败时尝试剩余 TLS，所有通道失败不循环重试', (tester) async {
    mirrors.failStart.addAll({_tcp, _tls});
    await _pumpHost(tester, container);
    mirrors.processes['phone']!.ended.complete(1);
    await tester.pumpAndSettle();
    expect(mirrors.starts.map((start) => start.id), ['phone', _tcp, _tls]);
    expect(mirrors.textures, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('没有同设备可用连接时保留停止状态，主动停止不触发查询', (tester) async {
    await _pumpHost(tester, container);
    await container
        .read(activeEmbeddedMirrorProvider('phone').notifier)
        .forceStop();
    await tester.pumpAndSettle();
    expect(adb.calls, isEmpty);
    expect(mirrors.starts, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('切换查询过程中关闭窗口，迟到结果不能启动新投屏', (tester) async {
    await _pumpHost(tester, container);
    adb.listGate = Completer<void>();
    mirrors.processes['phone']!.ended.complete(1);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    adb.listGate!.complete();
    await tester.pumpAndSettle();
    expect(mirrors.starts, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('恢复到 TCP 后再次断线，可以继续使用同设备 TLS 连接', (tester) async {
    await _pumpHost(tester, container);
    mirrors.processes['phone']!.ended.complete(1);
    await tester.pumpAndSettle();
    mirrors.processes[_tcp]!.ended.complete(1);
    await tester.pumpAndSettle();
    expect(mirrors.starts.map((start) => start.id), ['phone', _tcp, _tls]);
    expect(find.text('route:$_tls,texture:3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('断线后只有其他手机在线时保持停止状态，不显示无限加载', (tester) async {
    await _pumpHost(tester, container);
    adb.devices = 'other-phone device';
    adb.serials['other-phone'] = 'other-phone';
    mirrors.processes['phone']!.ended.complete(1);
    await tester.pumpAndSettle();
    expect(mirrors.starts, hasLength(1));
    expect(find.text('route:phone,texture:null'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
