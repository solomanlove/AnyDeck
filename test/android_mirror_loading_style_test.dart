import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/window/mirror/android_mirror_transport_host.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/embedded_scrcpy_service.dart';
import 'package:any_deck/core/scrcpy/mirror_transport_devices_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mirror_transport_fakes.dart';

/// 保留真实的 MaterialApp → 换线宿主 → Scaffold 层级，检查重连中的实际文字样式。
void main() {
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('重连提示使用主题正文样式 $language $brightness', (tester) async {
        tester.view.physicalSize = const Size(320, 420);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final gate = Completer<void>();
        final adb = TransportAdb()..listGate = gate;
        final scope = ProviderContainer(
          overrides: [
            adbServiceProvider.overrideWithValue(adb),
            embeddedScrcpyServiceProvider.overrideWithValue(TransportMirrors()),
            mirrorTransportDevicesProvider.overrideWith(
              (ref) => const Stream.empty(),
            ),
          ],
        );
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
          scope.dispose();
        });
        final theme = buildAppTheme(brightness);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: scope,
            child: MaterialApp(
              theme: theme,
              locale: Locale(language),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                GlobalMaterialLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              home: AndroidMirrorTransportHost(
                deviceId: 'phone',
                builder: (_, _) => const Scaffold(body: SizedBox.expand()),
              ),
            ),
          ),
        );

        // 阻塞假设备列表，让换线遮罩停留，不能只检查最终连接成功的页面。
        scope.read(mirrorDisconnectedProvider('phone').notifier).disconnected();
        await tester.pump();
        final label = find.text(
          language == 'zh'
              ? '正在启动投屏服务...'
              : 'Starting screen mirroring service...',
        );
        expect(label, findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        final text = tester.widget<RichText>(
          find.descendant(of: label, matching: find.byType(RichText)),
        );
        final style = text.text.style!;
        final body = Theme.of(tester.element(label)).textTheme.bodyMedium!;
        expect(style.fontSize, body.fontSize);
        expect(style.fontWeight, body.fontWeight);
        expect(style.color, body.color);
        expect(style.decoration, anyOf(isNull, TextDecoration.none));
        expect(tester.takeException(), isNull);

        gate.complete();
        await tester.pumpAndSettle();
        expect(label, findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
