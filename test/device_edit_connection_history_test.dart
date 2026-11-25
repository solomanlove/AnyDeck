import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/devices/widgets/device_info_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在实际编辑弹窗校验连接时间、历史区的位置与当前通道标识。
void main() {
  for (final scenario in [
    (
      locale: const Locale('zh'),
      online: false,
      title: '连接历史',
      current: '当前连接',
      unknown: '时间未记录',
    ),
    (
      locale: const Locale('en'),
      online: true,
      title: 'Connection history',
      current: 'Current connection',
      unknown: 'Time not recorded',
    ),
  ]) {
    testWidgets('编辑设备显示历史端口 ${scenario.locale}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(670, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
                  connectionHistory: [
                    (id: 'emulator-5556', connectedAt: null),
                    (
                      id: 'emulator-5600',
                      connectedAt: DateTime(2026, 11, 25, 14, 5, 9).toUtc(),
                    ),
                  ],
                  connections: const ['emulator-5600'],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Api36_16KB'), findsOneWidget);
      final history = find.text(scenario.title);
      expect(history, findsOneWidget);
      expect(
        tester.getTopLeft(history).dy,
        greaterThan(tester.getBottomLeft(find.byType(TextField).last).dy),
      );
      await tester.ensureVisible(find.text('emulator-5556'));
      await tester.pumpAndSettle();
      expect(find.text('emulator-5556'), findsOneWidget);
      expect(find.text('2026-11-25 14:05:09'), findsOneWidget);
      expect(find.text(scenario.unknown), findsOneWidget);
      expect(find.text('emulator-5600'), findsOneWidget);
      expect(
        find.text(scenario.current),
        scenario.online ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
