import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/window/mirror/mirror_settings_dialog.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 为弹窗提供指定的已保存画质，不启动原生服务。
class _Settings extends AppSettingsController {
  _Settings(this.maxSize, this.bitrate);

  final int maxSize;
  final int bitrate;

  @override
  AppSettings build() =>
      AppSettings(mirrorMaxSize: maxSize, mirrorVideoBitrate: bitrate);
}

void main() {
  for (final (maxSize, bitrate, locale, brightness) in [
    (1920, 16000000, 'zh', Brightness.light),
    (2340, 6500000, 'en', Brightness.dark),
  ]) {
    testWidgets('投屏设置可显示已保存画质 $maxSize / $bitrate', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsProvider.overrideWith(() => _Settings(maxSize, bitrate)),
            deviceSdkVersionProvider.overrideWith((ref, deviceId) => 34),
          ],
          child: MaterialApp(
            theme: buildAppTheme(brightness),
            locale: Locale(locale),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, child) => IconButton(
                  key: const Key('open-mirror-settings'),
                  icon: const Icon(Icons.settings),
                  onPressed: () => showMirrorSettingsDialog(
                    context: context,
                    ref: ref,
                    deviceId: 'test-device',
                    windowId: 'test-window',
                    isAlwaysOnTop: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-mirror-settings')));
      await tester.pumpAndSettle();

      final dropdowns = tester
          .widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>))
          .toList();
      expect(dropdowns, hasLength(2));
      expect(dropdowns.first.value, bitrate);
      expect(dropdowns.last.value, maxSize);
      expect(
        dropdowns.first.items!.where((item) => item.value == bitrate),
        hasLength(1),
      );
      expect(
        dropdowns.last.items!.where((item) => item.value == maxSize),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
