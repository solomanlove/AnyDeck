import 'dart:io';
import 'dart:ui' as ui;

import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_scan_backdrop.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_stage.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_drop_target.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final count in [0, 3]) {
      testWidgets('扫描圆心在有界布局与设备换行后仍与投递区重合 $count ${brightness.name}', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(480, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness),
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: const [Locale('zh'), Locale('en')],
            home: Scaffold(
              body: Center(
                child: HarmonyShareStage(
                  enabled: true,
                  busy: false,
                  peers: [
                    for (var i = 0; i < count; i++)
                      ShareCorePeer(
                        address: InternetAddress('192.168.1.${i + 2}'),
                        port: 44800,
                        name: 'Synthetic $i',
                      ),
                  ],
                  onPick: (_) {},
                  onDrop: (_, _) {},
                  onInvalidDrop: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final target = find.byWidgetPredicate(
          (widget) => widget is HarmonyShareDropTarget && widget.circular,
        );
        expect(
          tester.getCenter(find.byType(HarmonyShareScanBackdrop)),
          tester.getCenter(target),
        );
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('扫描产生真实帧变化且不重建前景，停用/无障碍/离页停止 ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(480, 340);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      var foregroundBuilds = 0;
      Widget host({
        bool active = true,
        bool ticker = true,
        bool reduced = false,
        bool accessible = false,
      }) => MaterialApp(
        theme: buildAppTheme(brightness),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(480, 340),
            disableAnimations: reduced,
            accessibleNavigation: accessible,
          ),
          child: TickerMode(
            enabled: ticker,
            child: RepaintBoundary(
              key: boundary,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  HarmonyShareScanBackdrop(active: active),
                  Center(
                    child: Builder(
                      builder: (_) {
                        foregroundBuilds++;
                        return const Icon(Icons.smartphone_outlined);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      Future<Uint8List> pixels() async => (await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage();
        try {
          return (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
        } finally {
          image.dispose();
        }
      }))!;

      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 100));
      final first = await pixels();
      await tester.pump(const Duration(milliseconds: 600));
      final next = await pixels();
      expect(listEquals(first, next), isFalse);
      expect(foregroundBuilds, 1);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      for (final stopped in [
        host(active: false),
        host(reduced: true),
        host(accessible: true),
        host(ticker: false),
      ]) {
        await tester.pumpWidget(stopped);
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
        final still = await pixels();
        await tester.pump(const Duration(milliseconds: 800));
        expect(listEquals(still, await pixels()), isTrue);
      }
      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
