import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/auxiliary_backend.dart';
import 'package:any_deck/core/scrcpy/device_capture_compatibility.dart';
import 'package:any_deck/features/apps/controller/device_auxiliary_controller.dart';
import 'package:any_deck/features/apps/widgets/camera_preview_view.dart';
import 'package:any_deck/features/apps/widgets/device_clipboard_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 所有传感器和剪贴板会话均替换为内存 fake。
class AuxiliaryFake implements AuxiliaryBackend {
  int starts = 0;
  int stops = 0;
  bool cancelled = false;
  bool muted = false;
  Completer<void>? pending;
  final texts = StreamController<String>.broadcast();
  final exit = Completer<void>();
  @override
  Stream<String> get clipboard => texts.stream;
  @override
  Future<void> get exited => exit.future;
  @override
  Future<void> start() async {
    starts++;
    await pending?.future;
  }

  @override
  Future<void> mute(bool value) async {
    muted = value;
  }

  @override
  Future<void> refresh() async {}
  @override
  void cancel() {
    cancelled = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    cancel();
  }
}

const mic = (deviceId: 'phone', microphone: true);
const clip = (deviceId: 'phone', microphone: false);
void main() {
  ProviderContainer container(AuxiliaryFake fake, {int? sdk = 31}) =>
      ProviderContainer(
        overrides: [
          captureSdkProvider('phone').overrideWith((ref) async => sdk),
          captureHostSupportedProvider.overrideWithValue(true),
          deviceOnlineProvider('phone').overrideWith((ref) => true),
          auxiliaryBackendFactoryProvider.overrideWithValue((_, _) => fake),
        ],
      );

  test('Android 10 和未知版本不启动麦克风', () async {
    for (final sdk in [29, null]) {
      final fake = AuxiliaryFake();
      final scope = container(fake, sdk: sdk);
      scope.listen(deviceAuxiliaryProvider(mic), (_, _) {});
      await scope.read(deviceAuxiliaryProvider(mic).notifier).start();
      expect(fake.starts, 0);
      expect(
        scope.read(deviceAuxiliaryProvider(mic)).messageKey,
        'auxUnsupported',
      );
      scope.dispose();
      await fake.texts.close();
    }
  });
  test('Android 11 可独立启停麦克风，静音不停止采集', () async {
    final fake = AuxiliaryFake();
    final scope = container(fake, sdk: 30);
    addTearDown(scope.dispose);
    addTearDown(fake.texts.close);
    scope.listen(deviceAuxiliaryProvider(mic), (_, _) {});
    final controller = scope.read(deviceAuxiliaryProvider(mic).notifier);
    await controller.start();
    await controller.toggleMute();
    expect(fake.muted, true);
    expect(fake.stops, 0);
    expect(scope.read(deviceAuxiliaryProvider(mic)).active, true);
    await controller.stop();
    expect(fake.cancelled, true);
    expect(fake.stops, 1);
  });
  test('启动中停止后忽略迟到完成', () async {
    final fake = AuxiliaryFake()..pending = Completer<void>();
    final scope = container(fake);
    addTearDown(scope.dispose);
    addTearDown(fake.texts.close);
    scope.listen(deviceAuxiliaryProvider(mic), (_, _) {});
    final controller = scope.read(deviceAuxiliaryProvider(mic).notifier);
    final start = controller.start();
    await Future<void>.delayed(Duration.zero);
    await controller.stop();
    fake.pending!.complete();
    await start;
    expect(scope.read(deviceAuxiliaryProvider(mic)).active, false);
    expect(fake.cancelled, true);
  });
  test('剪贴板按时间倒序保存在本地列表中，最新一条在最顶部', () async {
    final fake = AuxiliaryFake();
    final scope = container(fake);
    addTearDown(scope.dispose);
    addTearDown(fake.texts.close);
    scope.listen(deviceAuxiliaryProvider(clip), (_, _) {});
    final controller = scope.read(deviceAuxiliaryProvider(clip).notifier);
    await controller.start();
    fake.texts.add('旧内容');
    await Future<void>.delayed(const Duration(milliseconds: 130));
    fake.texts.add('新内容🙂');
    await Future<void>.delayed(const Duration(milliseconds: 130));
    final state = scope.read(deviceAuxiliaryProvider(clip));
    expect(state.history.length, 2);
    expect(state.history.first.text, '新内容🙂');
    expect(state.history[1].text, '旧内容');
    expect(state.text, '新内容🙂');
    controller.clearHistory();
    expect(scope.read(deviceAuxiliaryProvider(clip)).history, isEmpty);
  });
  test('剪贴板只保留最新内容，连接结束清空文本', () async {
    final fake = AuxiliaryFake();
    final scope = container(fake);
    addTearDown(scope.dispose);
    addTearDown(fake.texts.close);
    scope.listen(deviceAuxiliaryProvider(clip), (_, _) {});
    await scope.read(deviceAuxiliaryProvider(clip).notifier).start();
    fake.texts.add('旧内容');
    fake.texts.add('手机🙂剪贴板');
    await Future<void>.delayed(const Duration(milliseconds: 130));
    expect(scope.read(deviceAuxiliaryProvider(clip)).text, '手机🙂剪贴板');
    fake.exit.complete();
    await Future<void>.delayed(Duration.zero);
    expect(scope.read(deviceAuxiliaryProvider(clip)).text, isNull);
    expect(fake.cancelled, true);
  });

  for (final locale in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      for (final sdk in [29, 30, 31]) {
        testWidgets('版本门槛显示与按钮状态 $locale $brightness API $sdk', (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                captureSdkProvider('phone').overrideWith((ref) async => sdk),
                captureHostSupportedProvider.overrideWithValue(true),
                deviceOnlineProvider('phone').overrideWith((ref) => true),
              ],
              child: MaterialApp(
                locale: Locale(locale),
                theme: ThemeData(brightness: brightness),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizationsDelegate(),
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: const Scaffold(
                  body: SizedBox(
                    width: 620,
                    height: 400,
                    child: CameraPreviewView(deviceId: 'phone'),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final start = find.widgetWithText(
            FilledButton,
            locale == 'zh' ? '开始预览' : 'Start preview',
          );
          expect(
            tester.widget<FilledButton>(start).onPressed != null,
            sdk >= 31,
          );
          final microphone = find.widgetWithText(
            FilledButton,
            locale == 'zh' ? '开启麦克风' : 'Start microphone',
          );
          expect(
            tester.widget<FilledButton>(microphone).onPressed != null,
            sdk >= 30,
          );
          expect(find.textContaining('API $sdk'), findsWidgets);
          expect(tester.takeException(), isNull);
        });
      }
      testWidgets('剪贴板页面进入不自动读取 $locale $brightness', (tester) async {
        final fake = AuxiliaryFake();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              captureSdkProvider('phone').overrideWith((ref) async => 31),
              captureHostSupportedProvider.overrideWithValue(true),
              deviceOnlineProvider('phone').overrideWith((ref) => true),
              auxiliaryBackendFactoryProvider.overrideWithValue((_, _) => fake),
            ],
            child: MaterialApp(
              locale: Locale(locale),
              theme: ThemeData(brightness: brightness),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const Scaffold(
                body: SizedBox(
                  width: 620,
                  height: 500,
                  child: DeviceClipboardView(deviceId: 'phone'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(fake.starts, 0);
        await tester.tap(find.text(locale == 'zh' ? '开启读取' : 'Start reading'));
        await tester.pumpAndSettle();
        fake.texts.add('测试🙂');
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.text('测试🙂'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(fake.cancelled, true);
        await fake.texts.close();
      });
    }
  }
}
