import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/airplay/airplay_server_service.dart';
import 'package:any_deck/core/airplay/airplay_server_state.dart';
import 'package:any_deck/features/receivers/receiver_dashboard_tab.dart';
import 'package:any_deck/features/receivers/widgets/receiver_service_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AirPlay 未确认名称不冒充手机广播名，确认前后保持活跃会话状态', (tester) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    for (final brightness in Brightness.values) {
      for (final locale in ['zh', 'en']) {
        for (final activity in ['idle', 'mirror', 'video']) {
          for (final published in [false, true]) {
            const actualName = 'AnyDeck-会议室电脑-A7K2-AirPlay';
            final session = AirPlaySessionData(
              id: 1,
              serverName: actualName,
              rtspPort: 7000,
              videoPort: 7100,
              status: activity == 'mirror'
                  ? AirPlayServerStatus.mirrorStarting
                  : AirPlayServerStatus.idle,
              isVideoPlaying: activity == 'video',
              isPublished: published,
            );
            await tester.pumpWidget(
              ProviderScope(
                key: ValueKey('$brightness-$locale-$activity-$published'),
                overrides: [
                  appSettingsProvider.overrideWith(_ConfiguredSettings.new),
                  airplaySessionProvider.overrideWith(() => _Session(session)),
                ],
                child: MaterialApp(
                  theme: buildAppTheme(brightness),
                  localizationsDelegates: const [
                    AppLocalizationsDelegate(),
                    GlobalMaterialLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                  ],
                  supportedLocales: AppLocalizations.supportedLocales,
                  locale: Locale(locale),
                  home: const Scaffold(body: AirPlayReceiverCard()),
                ),
              ),
            );
            await tester.pump();
            final l10n = AppLocalizations(Locale(locale));
            final card = tester.widget<ReceiverServiceCard>(
              find.byType(ReceiverServiceCard),
            );
            expect(card.value, isTrue);
            expect(
              card.statusLabel,
              activity == 'mirror'
                  ? l10n
                        .t('receiverAirplayMirroring')
                        .replaceAll('{count}', '1')
                  : activity == 'video'
                  ? l10n.t('airplayVideoTitle')
                  : l10n.t(
                      published ? 'receiverWaiting' : 'receiverNamePending',
                    ),
            );
            expect(
              find.byKey(const Key('airplayNamePending')),
              published ? findsNothing : findsOneWidget,
            );
            expect(
              find.byKey(const Key('airplayBroadcastName')),
              published ? findsOneWidget : findsNothing,
            );
            if (!published) {
              expect(find.textContaining(actualName), findsNothing);
              if (activity == 'idle') {
                expect(
                  card.statusDetail,
                  l10n.t('receiverAirplayNamePendingDesc'),
                );
              }
            }
            expect(
              tester.widget<TextField>(find.byType(TextField)).controller!.text,
              '会议室电脑',
            );
            expect(tester.takeException(), isNull);
          }
        }
      }
    }
  });
}

/// 固定用户配置，验证异步广播名称不会替换原始可编辑名称。
class _ConfiguredSettings extends AppSettingsController {
  @override
  AppSettings build() => const AppSettings(airplayServerName: '会议室电脑');
}

/// 注入 native 发布状态，测试不注册 Bonjour 或启动投屏。
class _Session extends AirPlayServerNotifier {
  _Session(this.session);
  final AirPlaySessionData session;
  @override
  AirPlaySessionData? build() => session;
}
