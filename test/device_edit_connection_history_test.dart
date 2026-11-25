import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/devices/widgets/device_info_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在实际编辑弹窗校验历史端口的本地化，以及在线标识只绑定当前通道。
void main() {
  for (final scenario in [
    (locale: const Locale('zh'), online: false, title: '连接历史', current: '当前连接'),
    (
      locale: const Locale('en'),
      online: true,
      title: 'Connection history',
      current: 'Current connection',
    ),
  ]) {
    testWidgets('编辑设备显示历史端口 ${scenario.locale}', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: scenario.locale,
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(
              brightness: scenario.online ? Brightness.dark : Brightness.light,
            ),
            home: Scaffold(
              body: DeviceInfoEditDialog(
                device: RegisteredDevice(
                  id: 'emulator-5600',
                  model: 'Android Emulator',
                  status: scenario.online ? 'device' : 'offline',
                  isOnline: scenario.online,
                  emulatorAvdName: 'Api36_16KB',
                  connectionHistory: const ['emulator-5556', 'emulator-5600'],
                  connections: const ['emulator-5600'],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Api36_16KB'), findsOneWidget);
      expect(find.text(scenario.title), findsOneWidget);
      expect(find.text('emulator-5556'), findsOneWidget);
      expect(find.text('emulator-5600'), findsOneWidget);
      expect(
        find.text(scenario.current),
        scenario.online ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
