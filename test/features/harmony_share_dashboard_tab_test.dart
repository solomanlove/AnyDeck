import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/features/harmony_share/harmony_share_dashboard_tab.dart';
import 'package:any_deck/features/widgets/dashboard_header_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('鸿蒙互联在没有已连接手机时仍显示独立入口与接收状态', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: [AppLocalizationsDelegate()],
        home: Scaffold(body: HarmonyShareDashboardTab()),
      ),
    );
    expect(find.byType(DashboardHeaderBar), findsOneWidget);
    expect(find.textContaining('1 MiB'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });
}
