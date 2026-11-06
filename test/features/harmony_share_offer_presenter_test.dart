import 'dart:async';
import 'dart:io';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/nearby_share/harmony_share_incoming_notifications.dart';
import 'package:any_deck/features/harmony_share/controller/harmony_share_offer_presenter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harmony_share_notification_fakes.dart';

void main() {
  Future<BuildContext> host(
    WidgetTester tester, {
    String language = 'zh',
    Brightness brightness = Brightness.light,
  }) async {
    late BuildContext root;
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        theme: ThemeData(brightness: brightness),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: Builder(
          builder: (context) {
            root = context;
            return const Scaffold();
          },
        ),
      ),
    );
    return root;
  }

  testWidgets('请求失效只移除自己的确认 Route，保留其他弹窗', (tester) async {
    final root = await host(tester);
    final service = ShareOfferTestService();
    final incoming = HarmonyShareIncomingNotifications(
      service: service,
      bridge: ShareNotificationTestBridge(),
      enabled: () => false,
      text: (key) => key,
    );
    final presenter = HarmonyShareOfferPresenter(
      incoming: incoming,
      context: () => root,
    );
    service.offer(ShareIncomingOffer(InternetAddress('192.168.1.3'), 100));
    await tester.pumpAndSettle();
    expect(find.text('收到文件请求'), findsOneWidget);
    unawaited(
      showDialog<void>(
        context: root,
        builder: (_) => const AlertDialog(title: Text('Other dialog')),
      ),
    );
    await tester.pumpAndSettle();
    service.offer(null);
    await tester.pumpAndSettle();
    expect(find.text('Other dialog'), findsOneWidget);
    expect(service.decisions, isEmpty);
    presenter.dispose();
    incoming.dispose();
    service.dispose();
  });
  testWidgets('确认超时与用户拒绝走不同回调', (tester) async {
    final root = await host(tester);
    final service = ShareOfferTestService();
    final incoming = HarmonyShareIncomingNotifications(
      service: service,
      bridge: ShareNotificationTestBridge(),
      enabled: () => false,
      text: (key) => key,
    );
    final presenter = HarmonyShareOfferPresenter(
      incoming: incoming,
      context: () => root,
    );
    service.offer(ShareIncomingOffer(InternetAddress('192.168.1.3'), 100));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(service.expired, isTrue);
    expect(service.decisions, isEmpty);
    expect(find.text('收到文件请求'), findsNothing);
    presenter.dispose();
    incoming.dispose();
    service.dispose();
  });
  testWidgets('人工拒绝只记录一次，不被关闭回调当作接受', (tester) async {
    final root = await host(tester);
    final service = ShareOfferTestService();
    final incoming = HarmonyShareIncomingNotifications(
      service: service,
      bridge: ShareNotificationTestBridge(),
      enabled: () => false,
      text: (key) => key,
    );
    final presenter = HarmonyShareOfferPresenter(
      incoming: incoming,
      context: () => root,
    );
    service.offer(ShareIncomingOffer(InternetAddress('192.168.1.3'), 100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('拒绝'));
    await tester.pumpAndSettle();
    expect(service.decisions, [false]);
    expect(service.expired, isFalse);
    presenter.dispose();
    incoming.dispose();
    service.dispose();
  });
  testWidgets('弹窗尚未创建就销毁时不再访问已失效 context', (tester) async {
    final root = await host(tester);
    var reads = 0;
    final service = ShareOfferTestService();
    final incoming = HarmonyShareIncomingNotifications(
      service: service,
      bridge: ShareNotificationTestBridge(),
      enabled: () => false,
      text: (key) => key,
    );
    final presenter = HarmonyShareOfferPresenter(
      incoming: incoming,
      context: () {
        reads++;
        return root;
      },
    );
    service.offer(ShareIncomingOffer(InternetAddress('192.168.1.3'), 100));
    presenter.dispose();
    incoming.dispose();
    service.dispose();
    await tester.pumpAndSettle();
    expect(reads, 0);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('通知优先且十秒后展示主题自适应兜底 $language $brightness', (tester) async {
        final root = await host(
          tester,
          language: language,
          brightness: brightness,
        );
        final service = ShareOfferTestService();
        final bridge = ShareNotificationTestBridge();
        final incoming = HarmonyShareIncomingNotifications(
          service: service,
          bridge: bridge,
          enabled: () => true,
          text: root.l10n.t,
        );
        final presenter = HarmonyShareOfferPresenter(
          incoming: incoming,
          context: () => root,
        );
        service.offer(ShareIncomingOffer(InternetAddress.loopbackIPv4, 128));
        await tester.pumpAndSettle();
        expect(bridge.shown, hasLength(1));
        expect(find.byType(AlertDialog), findsNothing);
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        expect(find.text(root.l10n.t('harmonyShareIncoming')), findsOneWidget);
        expect(find.text(root.l10n.t('harmonyShareAccept')), findsOneWidget);
        expect(find.text(root.l10n.t('harmonyShareReject')), findsOneWidget);
        await tester.pump(const Duration(seconds: 20));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(service.expired, isTrue);
        expect(tester.takeException(), isNull);
        presenter.dispose();
        incoming.dispose();
        service.dispose();
      });
    }
  }

  testWidgets('点击通知正文打开兜底，接收动作只关闭自己的 Route', (tester) async {
    final root = await host(tester);
    final service = ShareOfferTestService();
    final bridge = ShareNotificationTestBridge();
    final incoming = HarmonyShareIncomingNotifications(
      service: service,
      bridge: bridge,
      enabled: () => true,
      text: root.l10n.t,
    );
    final presenter = HarmonyShareOfferPresenter(
      incoming: incoming,
      context: () => root,
    );
    service.offer(ShareIncomingOffer(InternetAddress.loopbackIPv4, 128));
    await tester.pumpAndSettle();
    incoming.handleClick(bridge.action('open'));
    await tester.pumpAndSettle();
    expect(find.text('收到文件请求'), findsOneWidget);
    unawaited(
      showDialog<void>(
        context: root,
        builder: (_) => const AlertDialog(title: Text('Other dialog')),
      ),
    );
    await tester.pumpAndSettle();
    incoming.handleClick(bridge.action('accept'));
    await tester.pumpAndSettle();
    expect(find.text('Other dialog'), findsOneWidget);
    expect(find.text('收到文件请求'), findsNothing);
    expect(service.decisions, [true]);
    presenter.dispose();
    incoming.dispose();
    service.dispose();
  });

  testWidgets('通知拒绝与已经点下的接收按钮竞争也只决定一次', (tester) async {
    final root = await host(tester);
    final service = ShareOfferTestService();
    final bridge = ShareNotificationTestBridge();
    final incoming = HarmonyShareIncomingNotifications(
      service: service,
      bridge: bridge,
      enabled: () => true,
      text: root.l10n.t,
    );
    final presenter = HarmonyShareOfferPresenter(
      incoming: incoming,
      context: () => root,
    );
    service.offer(ShareIncomingOffer(InternetAddress.loopbackIPv4, 128));
    await tester.pumpAndSettle();
    incoming.handleClick(bridge.action('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('接收'));
    incoming.handleClick(bridge.action('reject'));
    await tester.pumpAndSettle();
    expect(service.decisions, hasLength(1));
    expect(find.text('收到文件请求'), findsNothing);
    expect(tester.takeException(), isNull);
    presenter.dispose();
    incoming.dispose();
    service.dispose();
  });
}
