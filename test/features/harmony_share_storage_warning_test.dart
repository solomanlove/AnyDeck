import 'dart:async';
import 'dart:io';
import 'package:any_deck/core/nearby_share/harmony_share_send_queue.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_send_selection.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_queue_panel.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_storage_warning.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      testWidgets('保存容量错误在任务中显示双语恢复操作 $brightness $language', (tester) async {
        final l10n = AppLocalizations(Locale(language));
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
              body: HarmonyShareQueuePanel(
                items: [
                  ShareSendItem(
                    id: 'blocked',
                    peer: ShareCorePeer(
                      address: InternetAddress.loopbackIPv4,
                      port: 1234,
                      name: 'fixture',
                    ),
                    file: ShareSendFile(
                      file: File('/synthetic/file'),
                      bytes: 1,
                      modified: DateTime(2026),
                    ),
                    status: ShareSendStatus.failed,
                    error: 'history_buffer_full',
                  ),
                ],
                nativeBatch: true,
                running: false,
                onCancel: (_) {},
                onCancelAll: () {},
                onClear: () {},
              ),
            ),
          ),
        );
        expect(
          find.text(l10n.t('harmonyShareHistoryBufferFull')),
          findsOneWidget,
        );
        expect(find.text('history_buffer_full'), findsNothing);
        expect(tester.takeException(), isNull);
      });
      testWidgets('记录重试 480px $brightness $language 防重复，失败保留入口，关闭安全', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(480, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final l10n = AppLocalizations(Locale(language));
        var gate = Completer<bool>();
        var calls = 0;
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
              body: HarmonyShareStorageWarning(
                onRetry: () {
                  calls++;
                  return gate.future;
                },
              ),
            ),
          ),
        );
        expect(calls, 0);
        await tester.tap(find.text(l10n.t('harmonyShareRetryStorage')));
        await tester.pump();
        expect(calls, 1);
        expect(
          tester.widget<TextButton>(find.byType(TextButton)).onPressed,
          isNull,
        );
        gate.completeError(StateError('synthetic storage fault'));
        await tester.pumpAndSettle();
        expect(find.text(l10n.t('harmonyShareHistoryError')), findsOneWidget);
        expect(
          tester.widget<TextButton>(find.byType(TextButton)).onPressed,
          isNotNull,
        );
        gate = Completer<bool>();
        await tester.tap(find.text(l10n.t('harmonyShareRetryStorage')));
        await tester.pump();
        expect(calls, 2);
        await tester.pumpWidget(const SizedBox());
        gate.complete(true);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
