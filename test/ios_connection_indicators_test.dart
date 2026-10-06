import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/ios/ios_connection_type.dart';
import 'package:any_deck/core/providers/modules/registered_device_model.dart';
import 'package:any_deck/features/devices/widgets/device_connection_indicators.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wi-Fi 与 USB 图标仅依据 iOS 的真实通道，覆盖两种主题和语言。
void main() {
  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      testWidgets('iOS 连接图标 $brightness / $language', (tester) async {
        Future<void> show(
          Set<IosConnectionType> types, {
          bool online = true,
        }) async {
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: DeviceConnectionIndicators(
                  device: RegisteredDevice(
                    id: 'test-phone',
                    status: online ? 'device' : 'offline',
                    isOnline: online,
                    isIos: true,
                    iosConnectionTypes: types,
                  ),
                ),
              ),
            ),
          );
        }

        await show({IosConnectionType.network});
        expect(find.byIcon(CupertinoIcons.wifi), findsOneWidget);
        expect(find.byIcon(Icons.usb), findsNothing);
        expect(find.byIcon(CupertinoIcons.link), findsNothing);
        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
        expect(
          tooltip.message,
          language == 'zh' ? 'Wi-Fi（网络连接）' : 'Wi-Fi (Network connection)',
        );

        await show({IosConnectionType.usb, IosConnectionType.network});
        expect(find.byIcon(Icons.usb), findsOneWidget);
        expect(find.byIcon(CupertinoIcons.wifi), findsOneWidget);
        await show({IosConnectionType.usb});
        expect(find.byIcon(Icons.usb), findsOneWidget);
        expect(find.byIcon(CupertinoIcons.wifi), findsNothing);
        await show({});
        expect(find.byType(Icon), findsNothing);
        await show({IosConnectionType.network}, online: false);
        expect(find.byType(Icon), findsNothing);
      });
    }
  }
}
