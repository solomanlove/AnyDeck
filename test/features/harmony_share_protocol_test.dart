import 'dart:io';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/l10n/tables/app_l10n_huawei_share.dart';
import 'package:any_deck/app/theme/app_icon.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/app_asset_image.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/features/harmony_share/model/harmony_share_peer_state.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_peer_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('统一入口、帮助、网络错误和通知文案覆盖Huawei/Honor/AnyDeck', () {
    for (final values in [huaweiShareZh, huaweiShareEn]) {
      for (final key in [
        'harmonyShareGuide',
        'harmonyShareHint',
        'harmonyShareSubtitle',
        'harmonySharePeerUnavailable',
        'harmonyShareIndependent',
      ]) {
        expect(values[key], contains('AnyDeck'));
        expect(values[key], anyOf(contains('荣耀'), contains('HONOR')));
      }
      expect(
        values['harmonySharePhoneVersion'],
        anyOf(contains('荣耀'), contains('HONOR')),
      );
      expect(values['harmonyShareProtocol_huawei'], contains('AnyDeck'));
      expect(
        values['harmonyShareProtocol_honor'],
        anyOf(contains('荣耀'), contains('HONOR')),
      );
    }
    expect(huaweiShareZh['harmonyShareTitle'], '文件互传');
    expect(huaweiShareEn['harmonyShareTitle'], 'File transfer');
    expect(
      huaweiShareZh['harmonyShareNotificationResultHint'],
      contains('文件互传'),
    );
    expect(
      huaweiShareEn['harmonyShareNotificationResultHint'],
      contains('File transfer'),
    );
  });

  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      testWidgets('同一列表展示厂商Logo且不显示分享标签 ${brightness.name} $language', (
        tester,
      ) async {
        final values = language == 'zh' ? huaweiShareZh : huaweiShareEn;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness),
            locale: Locale(language),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Scaffold(
              body: Row(
                children: [
                  for (final protocol in ShareTransferProtocol.values)
                    SizedBox(
                      width: 180,
                      child: HarmonySharePeerAvatar(
                        state: HarmonySharePeerState(
                          available: true,
                          peer: ShareCorePeer(
                            address: InternetAddress('192.0.2.2'),
                            port: protocol == ShareTransferProtocol.honor
                                ? 5700
                                : 44800,
                            name: 'Synthetic device',
                            protocol: protocol,
                          ),
                        ),
                        enabled: true,
                        onPick: () {},
                        onDrop: (_) {},
                        onInvalidDrop: () {},
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.text(values['harmonyShareProtocol_honor']!),
          findsNothing,
        );
        expect(
          find.text(values['harmonyShareProtocol_huawei']!),
          findsNothing,
        );
        expect(find.byType(Tooltip), findsNothing);
        for (final entry in {
          ShareTransferProtocol.huawei: AppIcons.huawei,
          ShareTransferProtocol.honor: AppIcons.honor,
        }.entries) {
          final avatar = find.byWidgetPredicate(
            (widget) =>
                widget is HarmonySharePeerAvatar &&
                widget.state.peer.protocol == entry.key,
          );
          final logo = find.descendant(
            of: avatar,
            matching: find.byType(AppAssetImage),
          );
          expect(logo, findsOneWidget);
          expect(
            find.ancestor(of: logo, matching: find.byType(ClipOval)),
            findsOneWidget,
          );
          final image = tester.widget<Image>(
            find.descendant(of: logo, matching: find.byType(Image)),
          );
          expect((image.image as AssetImage).assetName, entry.value);
          expect(image.color, isNull);
          expect(image.fit, BoxFit.contain);
        }
        expect(find.byIcon(Icons.phone_android_rounded), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
