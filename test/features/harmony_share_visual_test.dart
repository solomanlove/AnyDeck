import 'dart:io';
import 'dart:ui' as ui;

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/features/harmony_share/harmony_share_dashboard_tab.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_panels.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可选导出 Widget 渲染图，无需启动或停止用户的 App。
/// 使用 --dart-define=HARMONY_CAPTURE_DIR=绝对路径；字体路径仅用于本机视觉验收。
void main() {
  const output = String.fromEnvironment('HARMONY_CAPTURE_DIR');
  const font = String.fromEnvironment('HARMONY_CAPTURE_FONT');
  for (final brightness in Brightness.values) {
    testWidgets('发现舞台与来件面板视觉布局 ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(1060, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (font.isNotEmpty) {
        await tester.runAsync(() async {
          final loader = FontLoader('CaptureFont');
          loader.addFont(
            File(font).readAsBytes().then((data) => ByteData.sublistView(data)),
          );
          await loader.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
        });
      }
      final key = GlobalKey();
      Widget host(Widget child) => MaterialApp(
        theme: buildAppTheme(brightness).copyWith(
          textTheme: buildAppTheme(
            brightness,
          ).textTheme.apply(fontFamily: font.isEmpty ? null : 'CaptureFont'),
        ),
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: RepaintBoundary(
          key: key,
          child: Scaffold(body: child),
        ),
      );
      Future<void> capture(String name) async {
        if (output.isEmpty) return;
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          await Directory(output).create(recursive: true);
          await File(
            '$output/$name-${brightness.name}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        });
      }

      await tester.pumpWidget(host(const HarmonyShareDashboardTab()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('empty');
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: Column(
              children: [
                HarmonyShareIdentity(enabled: true, onChanged: (_) {}),
                HarmonyShareStage(
                  peers: [
                    ShareCorePeer(
                      address: InternetAddress('192.168.1.2'),
                      port: 1234,
                      name: 'nova 12 Ultra',
                    ),
                  ],
                  enabled: true,
                  busy: false,
                  onPick: (_) {},
                  onDrop: (_, _) {},
                  onInvalidDrop: () {},
                ),
                const HarmonyShareRecent(paths: []),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('nearby');
      await tester.pumpWidget(
        host(
          const Center(
            child: HarmonyShareConfirmDialog(
              receiving: true,
              device: 'nova 12 Ultra',
              summary: '256 B',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('incoming');
    });
  }
}
