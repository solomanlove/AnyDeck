import 'dart:async';
import 'dart:convert';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/window/mirror/controller/mirror_clipboard_sync_controller.dart';
import 'package:any_deck/app/window/mirror/mirror_clipboard_dialog.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/auxiliary_backend.dart';
import 'package:any_deck/core/scrcpy/device_capture_compatibility.dart';
import 'package:any_deck/core/scrcpy/embedded_scrcpy_service.dart';
import 'package:any_deck/core/scrcpy/scrcpy_keycode_helper.dart';
import 'package:any_deck/features/apps/controller/device_auxiliary_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _ClipboardBackend implements AuxiliaryBackend {
  final texts = StreamController<String>.broadcast();
  final _exited = Completer<void>();
  @override
  Stream<String> get clipboard => texts.stream;
  @override
  Future<void> get exited => _exited.future;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {
    if (!_exited.isCompleted) _exited.complete();
  }

  @override
  Future<void> refresh() async {}
  @override
  Future<void> mute(bool muted) async {}
  @override
  void cancel() {}
}

class _ActiveMirror extends ActiveEmbeddedMirrorNotifier {
  _ActiveMirror() : super('phone');

  @override
  int? build() => 1;
}

void main() {
  test('scrcpy 4.0 SET_CLIPBOARD 按大端序编码 UTF-8 与 paste 标志', () {
    final bytes = ScrcpyKeycodeHelper.serializeSetClipboard(
      '小米🙂',
      paste: true,
    );
    final text = utf8.encode('小米🙂');
    expect(bytes.sublist(0, 10), [9, 0, 0, 0, 0, 0, 0, 0, 0, 1]);
    expect(bytes.sublist(10, 14), [0, 0, 0, text.length]);
    expect(bytes.sublist(14), text);
    expect(
      () => ScrcpyKeycodeHelper.serializeSetClipboard('a' * ((1 << 18) - 13)),
      throwsArgumentError,
    );
  });

  test('双向自动同步只处理变化，回写不形成循环，手动粘贴可独立触发', () async {
    String? hostClipboard = 'Mac 原文';
    final hostWrites = <String>[];
    final deviceWrites = <(String, bool)>[];
    final sync = MirrorClipboardSyncController(
      readHost: () async => hostClipboard,
      writeHost: (text) async {
        hostClipboard = text;
        hostWrites.add(text);
      },
      writeDevice: (text, {required paste}) async {
        deviceWrites.add((text, paste));
        return true;
      },
    );
    addTearDown(sync.dispose);

    await sync.start();
    expect(deviceWrites, isEmpty);

    sync.onDeviceText('手机首次复制');
    await Future<void>.delayed(Duration.zero);
    expect(hostWrites, ['手机首次复制']);
    await sync.pollHost();
    expect(deviceWrites, isEmpty);

    hostClipboard = 'Mac 新内容';
    await sync.pollHost();
    expect(deviceWrites, [('Mac 新内容', false)]);
    sync.onDeviceText('Mac 新内容');
    await Future<void>.delayed(Duration.zero);
    expect(hostWrites, ['手机首次复制']);

    await sync.pasteToDevice();
    expect(deviceWrites.last, ('Mac 新内容', true));

    sync.setAutoSync(false);
    hostClipboard = '只在 Mac 更新';
    await sync.pollHost();
    sync.onDeviceText('只在手机更新');
    await Future<void>.delayed(Duration.zero);
    expect(deviceWrites.length, 2);
    expect(hostWrites.length, 1);
    await sync.copyToHost();
    expect(hostWrites.last, '只在手机更新');
  });

  test('投屏子窗口没有 Registry SDK 缓存时仍能启动剪贴板监听', () async {
    final backend = _ClipboardBackend();
    final container = ProviderContainer(
      overrides: [
        windowIdProvider.overrideWithValue('mirror-window'),
        captureSdkProvider('phone').overrideWith((ref) async => null),
        captureHostSupportedProvider.overrideWithValue(true),
        deviceOnlineProvider('phone').overrideWith((ref) => true),
        activeEmbeddedMirrorProvider('phone').overrideWith(_ActiveMirror.new),
        auxiliaryBackendFactoryProvider.overrideWithValue((_, _) => backend),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(backend.texts.close);
    const key = (deviceId: 'phone', microphone: false);
    container.listen(deviceAuxiliaryProvider(key), (_, _) {});
    await container.read(deviceAuxiliaryProvider(key).notifier).start();
    expect(container.read(deviceAuxiliaryProvider(key)).active, true);
  });

  testWidgets('投屏弹窗展示双栏、自动同步与手机当前文本', (tester) async {
    final backend = _ClipboardBackend();
    addTearDown(backend.texts.close);
    String host = '小米';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return {'text': host};
          if (call.method == 'Clipboard.setData') {
            host = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          captureSdkProvider('phone').overrideWith((ref) async => 31),
          captureHostSupportedProvider.overrideWithValue(true),
          deviceOnlineProvider('phone').overrideWith((ref) => true),
          auxiliaryBackendFactoryProvider.overrideWithValue((_, _) => backend),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(
            body: MirrorClipboardDialog(
              deviceId: 'phone',
              deviceName: 'M2012K11AC',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('自动同步'), findsOneWidget);
    expect(find.text('M2012K11AC 剪贴板'), findsOneWidget);
    expect(find.text('小米'), findsOneWidget);
    backend.texts.add('手机文本');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.text('手机文本'), findsWidgets);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(320, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
