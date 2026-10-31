import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/settings/mirror_quality_preset.dart';
import 'package:any_deck/features/overview/widget/mirror_quality_presets.dart';
import 'package:any_deck/features/overview/widget/software_manual_content.dart';

/// 隔离原生服务初始化，仍调用实际设置持久化与广播方法。
class _Settings extends AppSettingsController {
  @override
  AppSettings build() => const AppSettings();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const windows = MethodChannel('mixin.one/desktop_multi_window');
  const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
  final calls = <Map<dynamic, dynamic>>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    messenger.setMockMethodCallHandler(
      windows,
      (call) async => call.method == 'getAllWindows'
          ? [
              {'windowId': 'other', 'windowArgument': '{"kind":"mirror"}'},
            ]
          : null,
    );
    messenger.setMockMethodCallHandler(channels, (call) async {
      if (call.method == 'invokeMethod') calls.add(call.arguments as Map);
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(windows, null);
    messenger.setMockMethodCallHandler(channels, null);
  });

  for (final id in ['', 'child']) {
    test('预设持久化两个参数并通过现有窗口通道广播 $id', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(_Settings.new),
          windowIdProvider.overrideWithValue(id),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(appSettingsProvider.notifier);
      for (final preset in MirrorQualityPreset.values) {
        calls.clear();
        await controller.setMirrorQualityPreset(preset);
        final settings = container.read(appSettingsProvider);
        expect(MirrorQualityPreset.matching(settings), preset);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('settings.mirrorVideoBitrate'), preset.bitrate);
        expect(prefs.getInt('settings.mirrorMaxSize'), preset.maxSize);
        expect(
          calls.any(
            (call) =>
                call['method'] == 'update_video_bitrate' &&
                call['arguments'] == preset.bitrate,
          ),
          true,
        );
        expect(
          calls.any(
            (call) =>
                call['method'] == 'update_max_size' &&
                call['arguments'] == preset.maxSize,
          ),
          true,
        );
        expect(
          settings.mirrorAudioEnabled,
          const AppSettings().mirrorAudioEnabled,
        );
      }
      await controller.setMirrorMaxSize(1440, broadcast: false);
      expect(
        MirrorQualityPreset.matching(container.read(appSettingsProvider)),
        null,
      );
    });
  }

  for (final lang in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('说明书跨平台内容与画质预设 $lang $brightness', (tester) async {
        final container = ProviderContainer(
          overrides: [appSettingsProvider.overrideWith(_Settings.new)],
        );
        addTearDown(container.dispose);
        Widget harness(Widget child) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: Locale(lang),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              ...GlobalMaterialLocalizations.delegates,
            ],
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: SizedBox(
                width: 520,
                child: SingleChildScrollView(child: child),
              ),
            ),
          ),
        );
        await tester.pumpWidget(harness(const MirrorQualityPresets()));
        await tester.tap(find.text(lang == 'zh' ? '流畅' : 'Smooth'));
        await tester.pumpAndSettle();
        expect(container.read(appSettingsProvider).mirrorVideoBitrate, 2000000);
        expect(find.textContaining('720 px'), findsOneWidget);
        expect(
          find.textContaining(lang == 'zh' ? '下次启动' : 'next start'),
          findsOneWidget,
        );
        expect(tester.takeException(), null);
        await tester.pumpWidget(harness(const SoftwareManualContent()));
        expect(
          find.textContaining('Android', findRichText: false),
          findsWidgets,
        );
        expect(find.textContaining('iOS'), findsWidgets);
        expect(find.textContaining('HarmonyOS'), findsWidgets);
        expect(find.textContaining('AI MCP'), findsWidgets);
        expect(find.textContaining('connectionState'), findsOneWidget);
        expect(tester.takeException(), null);
      });
    }
  }
}
