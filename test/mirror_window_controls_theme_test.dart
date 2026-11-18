import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/window/mirror/widget/mirror_window_title_bar.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/device_capture_compatibility.dart';
import 'package:any_deck/core/virtual_camera/virtual_camera_controller.dart';
import 'package:any_deck/core/virtual_camera/virtual_camera_state.dart';
import 'package:any_deck/features/control/widgets/virtual_camera_controls.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 固定正在供帧的会话，避免测试启动原生扩展、轮询或设备命令。
class _Camera extends VirtualCameraController {
  int stops = 0;

  @override
  VirtualCameraState build() => const VirtualCameraState(
    supported: true,
    installed: true,
    activation: 'ready',
    enabled: true,
    streaming: true,
    deviceId: 'phone',
    front: true,
  );

  @override
  Future<void> disable() async {
    stops++;
    state = const VirtualCameraState(
      supported: true,
      installed: true,
      activation: 'ready',
      deviceId: 'phone',
      front: true,
    );
  }
}

/// 保持同一页面实例换色，移除全局 Cupertino 兜底以检验组件自身绑定。
Widget _app(
  ValueNotifier<AppThemeColor> color,
  Brightness brightness,
  Widget child,
) => ValueListenableBuilder<AppThemeColor>(
  valueListenable: color,
  builder: (_, selected, _) => MaterialApp(
    theme: buildAppTheme(brightness, themeColor: selected).copyWith(
      platform: TargetPlatform.macOS,
      cupertinoOverrideTheme: const CupertinoThemeData(applyThemeToAll: false),
    ),
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    home: Scaffold(body: child),
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('投屏置顶与音频运行标记实时换色并保留状态 $brightness', (tester) async {
      final color = ValueNotifier(AppThemeColor.blue);
      final pinned = ValueNotifier(true);
      addTearDown(color.dispose);
      addTearDown(pinned.dispose);
      var toggles = 0;
      await tester.pumpWidget(
        _app(
          color,
          brightness,
          ValueListenableBuilder<bool>(
            valueListenable: pinned,
            builder: (_, value, _) => Builder(
              builder: (context) => MirrorWindowTitleBar(
                deviceName: 'AnyDeck 测试设备',
                backgroundColor: Theme.of(context).colorScheme.surface,
                isIos: false,
                isAudioForwarded: true,
                isMirrorActive: false,
                isAlwaysOnTop: value,
                isFullScreen: false,
                onTitleHoverChanged: (_) {},
                onRetry: () {},
                onToggleAlwaysOnTop: () {
                  toggles++;
                  pinned.value = !pinned.value;
                },
                onToggleFullScreen: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final header = tester.element(find.byType(MirrorWindowTitleBar));
      final l10n = AppLocalizations(const Locale('zh'));
      for (final selected in [AppThemeColor.blue, AppThemeColor.pink]) {
        color.value = selected;
        await tester.pumpAndSettle();
        expect(
          tester.widget<Icon>(find.byIcon(CupertinoIcons.pin_fill)).color,
          selected.color,
        );
        final dot = tester.widget<Container>(
          find.descendant(
            of: find.byTooltip(l10n.t('audioForwardingTooltip')),
            matching: find.byType(Container),
          ),
        );
        expect((dot.decoration! as BoxDecoration).color, selected.color);
        expect(tester.element(find.byType(MirrorWindowTitleBar)), same(header));
        expect(pinned.value, isTrue);
        expect(toggles, 0);
      }
      await tester.tap(find.byIcon(CupertinoIcons.pin_fill));
      await tester.pumpAndSettle();
      expect(toggles, 1);
      expect(pinned.value, isFalse);
      expect(
        tester.widget<Icon>(find.byIcon(CupertinoIcons.pin)).color,
        Theme.of(
          tester.element(find.byType(MirrorWindowTitleBar)),
        ).appColors.toolbarForeground,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('系统摄像头真实开关轨道实时换色并保留运行与镜头 $brightness', (tester) async {
      final color = ValueNotifier(AppThemeColor.blue);
      addTearDown(color.dispose);
      final camera = _Camera();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            virtualCameraHostProvider.overrideWithValue(true),
            virtualCameraProvider.overrideWith(() => camera),
            deviceOnlineProvider('phone').overrideWith((ref) => true),
            captureSdkProvider('phone').overrideWith((ref) async => 36),
          ],
          child: _app(
            color,
            brightness,
            const SingleChildScrollView(
              child: VirtualCameraControls(deviceId: 'phone'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(VirtualCameraControls));
      final control = find.descendant(
        of: find.byKey(const ValueKey('virtual-camera-enable')),
        matching: find.byType(Switch),
      );
      for (final selected in [AppThemeColor.blue, AppThemeColor.pink]) {
        color.value = selected;
        await tester.pumpAndSettle();
        final toggle = tester.widget<Switch>(control);
        expect(toggle.value, isTrue);
        expect(
          toggle.activeThumbColor,
          Theme.of(tester.element(control)).colorScheme.onPrimary,
        );
        final paint = find.descendant(
          of: control,
          matching: find.byWidgetPredicate(
            (widget) => widget is CustomPaint && widget.painter != null,
          ),
        );
        expect(paint, findsOneWidget);
        expect(paint, paints..rrect(color: selected.color));
        expect(
          tester
              .widget<DropdownButton<bool>>(find.byType(DropdownButton<bool>))
              .value,
          isTrue,
        );
        expect(tester.state(find.byType(VirtualCameraControls)), same(state));
        expect(camera.stops, 0);
      }
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(camera.stops, 1);
      expect(tester.widget<Switch>(control).value, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
