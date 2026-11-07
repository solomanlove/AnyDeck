import 'dart:io';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/features/harmony_share/harmony_share_dashboard_tab.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_panels.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_stage.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_scan_backdrop.dart';
import 'package:any_deck/features/widgets/dashboard_header_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  Widget host(
    Widget child, {
    Brightness brightness = Brightness.light,
    String language = 'zh',
  }) => MaterialApp(
    theme: buildAppTheme(brightness),
    locale: Locale(language),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    home: Scaffold(body: child),
  );

  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      testWidgets('无手机独立页面 ${brightness.name} $language', (tester) async {
        tester.view.physicalSize = const Size(1000, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          host(
            const HarmonyShareDashboardTab(),
            brightness: brightness,
            language: language,
          ),
        );
        expect(find.byType(DashboardHeaderBar), findsOneWidget);
        final l10n = tester.element(find.byType(HarmonyShareDashboardTab)).l10n;
        expect(find.text(l10n.t('harmonyShareNearby')), findsNothing);
        expect(find.text(l10n.t('harmonyShareIndependent')), findsNothing);
        expect(find.byType(Chip), findsNothing);
        // 身份栏直接位于卡片顶部，仅保留边框，避免删掉文案后仍有空白标题区。
        final identity = find.byType(HarmonyShareIdentity);
        final card = find
            .ancestor(of: identity, matching: find.byType(Container))
            .first;
        expect(
          tester.getTopLeft(identity).dy - tester.getTopLeft(card).dy,
          inInclusiveRange(0, 1),
        );
        expect(find.textContaining('1 GiB'), findsNothing);
        expect(find.text(l10n.t('harmonySharePhoneVersion')), findsOneWidget);
        expect(l10n.t('harmonySharePhoneVersion'), contains('6.0.0.112'));
        // 背景绘制层必须覆盖上下栏，不能只在中央舞台内绘制。
        final backdrop = tester.getRect(find.byType(HarmonyShareScanBackdrop));
        expect(backdrop.top, lessThanOrEqualTo(tester.getRect(identity).top));
        expect(
          backdrop.bottom,
          greaterThanOrEqualTo(
            tester.getRect(find.text(l10n.t('harmonyShareHelp'))).bottom,
          ),
        );
        expect(find.byType(Switch), findsOneWidget);
        expect(find.byType(HarmonyShareStage), findsOneWidget);
        expect(tester.takeException(), isNull);
        final guide = find.text(
          language == 'zh'
              ? '找不到设备？查看连接指引 →'
              : 'Device missing? Connection guide →',
        );
        await tester.ensureVisible(guide);
        await tester.tap(guide);
        await tester.pumpAndSettle();
        expect(find.textContaining('Wi-Fi'), findsWidgets);
        expect(find.byType(AlertDialog), findsOneWidget);
      });
    }
  }

  testWidgets('多设备头像选择准确目标，不再显示中央选择文件入口', (tester) async {
    final peers = [
      ShareCorePeer(
        address: InternetAddress('192.168.1.2'),
        port: 1234,
        name: 'nova 12 Ultra',
      ),
      ShareCorePeer(
        address: InternetAddress('192.168.1.3'),
        port: 1234,
        name: 'Mate',
      ),
    ];
    ShareCorePeer? picked;
    await tester.pumpWidget(
      host(
        HarmonyShareStage(
          peers: peers,
          enabled: true,
          busy: false,
          onPick: (peer) => picked = peer,
          onDrop: (_, _) {},
          onInvalidDrop: () {},
        ),
      ),
    );
    await tester.tap(find.text('Mate'));
    expect(picked, same(peers.last));
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('忙碌时禁用设备和选文件入口', (tester) async {
    var picked = false;
    await tester.pumpWidget(
      host(
        HarmonyShareStage(
          peers: [
            ShareCorePeer(
              address: InternetAddress('192.168.1.2'),
              port: 1234,
              name: 'nova',
            ),
          ],
          enabled: true,
          busy: true,
          onPick: (_) => picked = true,
          onDrop: (_, _) {},
          onInvalidDrop: () {},
        ),
      ),
    );
    await tester.tap(find.text('nova'));
    expect(picked, isFalse);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('来件只展示摘要并允许明确拒绝', (tester) async {
    bool? accepted;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => accepted = await showDialog<bool>(
              context: context,
              builder: (_) => const HarmonyShareConfirmDialog(
                receiving: true,
                device: 'nova',
                summary: '256 B',
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('收到文件请求'), findsOneWidget);
    expect(find.textContaining('30 秒'), findsOneWidget);
    await tester.tap(find.text('拒绝'));
    await tester.pumpAndSettle();
    expect(accepted, isFalse);
  });

  testWidgets('窄窗口不溢出', (tester) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(const HarmonyShareDashboardTab()));
    expect(tester.takeException(), isNull);
  });
}
