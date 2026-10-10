import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/features/performance/performance_widgets.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';

void main() {
  Widget buildTestWidget({
    required String uptime,
    required int batteryLevel,
    required bool isCharging,
  }) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PerformanceTopStatusRow(
          uptime: uptime,
          batteryLevel: batteryLevel,
          isCharging: isCharging,
        ),
      ),
    );
  }

  testWidgets('displays charging bolt icon when device is charging', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        uptime: '00时02分13秒',
        batteryLevel: 99,
        isCharging: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('99%'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.battery_100), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.bolt_fill), findsOneWidget);

    final boltIcon = tester.widget<Icon>(find.byIcon(CupertinoIcons.bolt_fill));
    expect(boltIcon.color, const Color(0xff00c853));

    final batteryIcon = tester.widget<Icon>(find.byIcon(CupertinoIcons.battery_100));
    expect(batteryIcon.color, const Color(0xff00c853));
  });

  testWidgets('keeps existing style without bolt icon when device is not charging', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        uptime: '00时02分13秒',
        batteryLevel: 99,
        isCharging: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('99%'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.battery_100), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.bolt_fill), findsNothing);

    final batteryIcon = tester.widget<Icon>(find.byIcon(CupertinoIcons.battery_100));
    expect(batteryIcon.color, const Color(0xff5f6b6e));
  });
}
