import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/receivers/receiver_dashboard_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('投屏接收页集中展示 AirPlay 与 DLNA 服务', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(body: ReceiverDashboardTab()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('投屏接收'), findsOneWidget);
    expect(find.text('AirPlay 投屏'), findsOneWidget);
    expect(find.text('DLNA 视频'), findsOneWidget);
    expect(
      find.text('接收支持 DLNA 的视频 App 投放的媒体，不是设备屏幕镜像。'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('airplayReceiverSwitch')), findsOneWidget);
    expect(find.byKey(const Key('dlnaReceiverSwitch')), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('AnyDeck-DLNA'), findsNWidgets(2));
    expect(find.byKey(const Key('receiverAppSupportGuide')), findsOneWidget);
    expect(find.text('常见视频 App 投放示例'), findsOneWidget);
    expect(find.text('哔哩哔哩'), findsOneWidget);
    expect(find.text('抖音'), findsOneWidget);
    expect(find.text('腾讯视频'), findsOneWidget);
    expect(find.text('爱奇艺'), findsOneWidget);
    expect(find.text('小红书'), findsOneWidget);
    expect(find.text('当前版本实测支持 DLNA，不支持 AirPlay'), findsOneWidget);
    expect(find.text('待确认'), findsNothing);
  });
}
