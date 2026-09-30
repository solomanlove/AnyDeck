import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/devices/widgets/device_wireless_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 固定 UI 状态，Widget 测试不会启动后台设备发现或连接。
class _WirelessUiState extends WirelessConnectionNotifier {
  _WirelessUiState(this.value);
  final AdbWirelessState value;
  @override
  Map<String, AdbWirelessState> build() => {'PHONE': value};
}

void main() {
  const device = RegisteredDevice(
    id: 'PHONE',
    serial: 'PHONE',
    status: 'device',
    isOnline: true,
  );
  for (final locale in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('连接忙碌时禁用按钮，失败文案适配 $locale $brightness', (tester) async {
        Future<void> render(AdbWirelessState status) async {
          await tester.pumpWidget(
            ProviderScope(
              key: UniqueKey(),
              overrides: [
                wirelessConnectionProvider.overrideWith(
                  () => _WirelessUiState(status),
                ),
              ],
              child: MaterialApp(
                locale: Locale(locale),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizationsDelegate(),
                  ...GlobalMaterialLocalizations.delegates,
                ],
                theme: ThemeData(brightness: brightness),
                home: const Scaffold(
                  body: SizedBox(
                    width: 260,
                    child: Column(
                      children: [
                        DeviceWirelessControls(device: device),
                        DeviceWirelessStatusLabel(device: device),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
        }

        await render(
          const AdbWirelessState(
            deviceId: 'PHONE',
            messageKey: 'wirelessDiscovering',
            busy: true,
          ),
        );
        expect(
          tester.widget<IconButton>(find.byType(IconButton).first).onPressed,
          isNull,
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await render(
          const AdbWirelessState(
            deviceId: 'PHONE',
            messageKey: 'wirelessNoIp',
            failed: true,
          ),
        );
        expect(
          tester.widget<IconButton>(find.byType(IconButton).first).onPressed,
          isNotNull,
        );
        expect(
          find.text(AppLocalizations(Locale(locale)).t('wirelessNoIp')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
