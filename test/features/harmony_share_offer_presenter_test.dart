import 'dart:async';
import 'dart:io';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/features/harmony_share/controller/harmony_share_offer_presenter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Service extends ChangeNotifier implements HarmonyShareService {
  @override
  ShareIncomingOffer? pendingOffer;
  @override
  final Map<String, ShareCorePeer> peers = {};
  final decisions = <bool>[];
  bool expired = false;
  void offer(ShareIncomingOffer? value) {
    pendingOffer = value;
    notifyListeners();
  }

  @override
  void decide(bool accept) {
    decisions.add(accept);
    offer(null);
  }

  @override
  void expireOffer(ShareIncomingOffer offer) {
    expired = true;
    this.offer(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<BuildContext> host(WidgetTester tester) async {
    late BuildContext root;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
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
    final service = _Service();
    final presenter = HarmonyShareOfferPresenter(
      service: service,
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
    service.dispose();
  });
  testWidgets('确认超时与用户拒绝走不同回调', (tester) async {
    final root = await host(tester);
    final service = _Service();
    final presenter = HarmonyShareOfferPresenter(
      service: service,
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
    service.dispose();
  });
  testWidgets('人工拒绝只记录一次，不被关闭回调当作接受', (tester) async {
    final root = await host(tester);
    final service = _Service();
    final presenter = HarmonyShareOfferPresenter(
      service: service,
      context: () => root,
    );
    service.offer(ShareIncomingOffer(InternetAddress('192.168.1.3'), 100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('拒绝'));
    await tester.pumpAndSettle();
    expect(service.decisions, [false]);
    expect(service.expired, isFalse);
    presenter.dispose();
    service.dispose();
  });
  testWidgets('弹窗尚未创建就销毁时不再访问已失效 context', (tester) async {
    final root = await host(tester);
    var reads = 0;
    final service = _Service();
    final presenter = HarmonyShareOfferPresenter(
      service: service,
      context: () {
        reads++;
        return root;
      },
    );
    service.offer(ShareIncomingOffer(InternetAddress('192.168.1.3'), 100));
    presenter.dispose();
    service.dispose();
    await tester.pumpAndSettle();
    expect(reads, 0);
    expect(tester.takeException(), isNull);
  });
}
