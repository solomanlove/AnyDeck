import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/l10n/tables/app_l10n_virtual_camera.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/device_capture_compatibility.dart';
import 'package:any_deck/core/virtual_camera/virtual_camera_controller.dart';
import 'package:any_deck/features/apps/widgets/camera_preview_view.dart';
import 'package:any_deck/features/control/widgets/virtual_camera_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('anydeck/virtual_camera');
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Widget app(
    Widget child, {
    String locale = 'zh',
    Brightness brightness = Brightness.light,
    int sdk = 36,
  }) => ProviderScope(
    overrides: [
      virtualCameraHostProvider.overrideWithValue(true),
      deviceOnlineProvider('phone').overrideWith((ref) => true),
      captureSdkProvider('phone').overrideWith((ref) async => sdk),
      captureHostSupportedProvider.overrideWithValue(true),
      concurrentCameraSupportedProvider(
        'phone',
      ).overrideWith((ref) async => false),
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
      home: Scaffold(body: child),
    ),
  );

  test('系统摄像头的中英文键完整一致', () {
    expect(virtualCameraZh.keys.toSet(), virtualCameraEn.keys.toSet());
    expect(virtualCameraEn.values.every((text) => text.isNotEmpty), true);
  });

  for (final locale in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('小窗口显示扩展状态并允许停止共享 $locale $brightness', (tester) async {
        var enabled = true;
        final calls = <String>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'configure') {
            expect(call.arguments, {'enabled': false});
            enabled = false;
          }
          return {
            'supported': true,
            'installed': true,
            'activation': 'ready',
            'enabled': enabled,
            'deviceId': 'phone',
            'streaming': enabled,
          };
        });
        await tester.pumpWidget(
          app(
            const SizedBox(
              width: 340,
              height: 260,
              child: SingleChildScrollView(
                child: VirtualCameraControls(deviceId: 'phone'),
              ),
            ),
            locale: locale,
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(calls, ['status']);
        await tester.ensureVisible(
          find.byKey(const ValueKey('virtual-camera-enable')),
        );
        await tester.pumpAndSettle();
        final toggle = tester.widget<SwitchListTile>(
          find.byType(SwitchListTile),
        );
        expect(toggle.value, true);
        toggle.onChanged!(false);
        await tester.pumpAndSettle();
        expect(enabled, false);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets('旧 Android 设备无法开启系统摄像头', (tester) async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'supported': true,
        'installed': true,
        'activation': 'ready',
      },
    );
    await tester.pumpWidget(
      app(const VirtualCameraControls(deviceId: 'phone'), sdk: 30),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('共享手机镜头时禁用本地预览，关闭预览UI不会停止共享', (tester) async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return {
        'supported': true,
        'installed': true,
        'activation': 'ready',
        'enabled': true,
        'deviceId': 'phone',
      };
    });
    await tester.pumpWidget(
      app(
        const SizedBox(
          width: 620,
          height: 400,
          child: CameraPreviewView(deviceId: 'phone'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '开始预览'),
    );
    expect(button.onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(calls, ['status']);
  });
}
