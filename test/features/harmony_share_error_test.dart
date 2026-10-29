import 'dart:async';
import 'dart:io';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/nearby_share/share_transfer_record.dart';
import 'package:any_deck/features/harmony_share/harmony_share_dashboard_tab.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_batch_details.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_format.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_record_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 使用生产异常的 toString 与公开 IPC 错误信封，不访问网络、手机或用户文件。
void main() {
  for (final language in ['zh', 'en']) {
    final l10n = AppLocalizations(Locale(language));
    test('实际异常与收发错误提供恢复建议 $language', () {
      final cases = <Object, String>{
        const FileSystemException('Share Core is not bundled'):
            'harmonyShareCoreUnavailable',
        const FormatException('Incompatible experimental transfer contract'):
            'harmonyShareCoreUnavailable',
        const FileSystemException('No active IPv4 network with netmask'):
            'harmonyShareNetworkUnavailable',
        const FileSystemException(
          'Receive directory unavailable',
          '/synthetic',
        ): 'harmonyShareDirectoryError',
        const FileSystemException('Downloads unavailable'):
            'harmonyShareDirectoryError',
        const FileSystemException('Queued file changed or unavailable'):
            'harmonyShareSourceChanged',
        const FormatException('Only nonempty regular files up to 1 GiB'):
            'harmonyShareSelectionLimit',
        const FormatException('Invalid local name'):
            'harmonyShareLocalNameInvalid',
        StateError('outbox_full'): 'harmonyShareOutboxFull',
        StateError('outbox_cancelling'): 'harmonyShareOutboxUnavailable',
        StateError('Settings active'): 'harmonyShareSettingsBusy',
        StateError('Batch transfer cancelled'): 'harmonyShareStatus_cancelled',
        TimeoutException('Batch transfer timed out'):
            'harmonyShareOperationTimedOut',
        TimeoutException('Future not completed', const Duration(seconds: 3)):
            'harmonyShareOperationTimedOut',
        StateError('Share Core send_failed: connect tcp_failed'):
            'harmonySharePeerUnavailable',
        StateError('Share Core send_failed: offer phone_rejected'):
            'harmonySharePeerRejected',
        StateError('Share Core send_failed: transfer dfile_timeout'):
            'harmonyShareOperationTimedOut',
        StateError('Share Core send_failed: prepare invalid_files'):
            'harmonyShareFileUnavailable',
        'receive_failed: decision_timeout': 'harmonyShareOperationTimedOut',
        'receive_failed: deadline': 'harmonyShareOperationTimedOut',
        'receive_failed: dfile_timeout': 'harmonyShareOperationTimedOut',
        'receive_failed: dfile_terminated': 'harmonyShareOperationFailed',
        'receive_failed: invalid_batch': 'harmonyShareReceiveValidationFailed',
        'receive_failed: unsupported_network_mode': 'harmonyShareDirectModeUnsupported',
        'receive_failed: insufficient_space': 'harmonyShareInsufficientSpace',
        'receive_failed: size_mismatch': 'harmonyShareReceiveValidationFailed',
        'history_buffer_full': 'harmonyShareHistoryBufferFull',
      };
      for (final entry in cases.entries) {
        final expected = l10n.t(entry.value);
        expect(expected, isNot(entry.value), reason: 'Missing translation');
        expect(
          formatShareError('${entry.key}', l10n.t),
          expected,
          reason: '${entry.key}',
        );
      }
    });
    test('未知错误不透出路径，不从任意子串或错误方向猜测原因 $language', () {
      for (final raw in [
        "FileSystemException: Cannot open file, path = '/synthetic/phone_rejected'",
        'send_failed: insufficient_space',
        'receive_failed: phone_rejected',
        'send_failed: unsupported_network_mode',
        'prefix receive_failed: insufficient_space',
        'receive_failed: insufficient_space trailing',
        'receive_failed: insufficient_space\nuntrusted',
        'unknown /synthetic/tcp_failed',
        'send_failed',
        '',
      ]) {
        expect(
          formatShareError(raw, l10n.t),
          l10n.t('harmonyShareOperationFailed'),
          reason: raw,
        );
      }
    });

    for (final brightness in Brightness.values) {
      testWidgets('直连模式限制及原始诊断，480px ${brightness.name} $language', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(480, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = HarmonyShareService.instance;
        final oldError = service.error;
        addTearDown(() => service.error = oldError);
        const raw = 'receive_failed: unsupported_network_mode';
        service.error = raw;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness),
            locale: Locale(language),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: const Scaffold(body: HarmonyShareDashboardTab()),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(l10n.t('harmonyShareDirectModeUnsupported')),
          findsOneWidget,
        );
        expect(find.text(raw), findsNothing);
        final details = find.byTooltip(l10n.t('harmonyShareErrorDetails'));
        await tester.ensureVisible(details);
        await tester.tap(details);
        await tester.pumpAndSettle();
        expect(find.text(raw), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
      testWidgets('错误提示与主动诊断，480px ${brightness.name} $language', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(480, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Widget host(Widget child) => MaterialApp(
          theme: buildAppTheme(brightness),
          locale: Locale(language),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(body: child),
        );
        final service = HarmonyShareService.instance;
        final oldError = service.error;
        addTearDown(() => service.error = oldError);
        final raw = StateError(
          'Share Core send_failed: connect tcp_failed',
        ).toString();
        service.error = raw;
        await tester.pumpWidget(host(const HarmonyShareDashboardTab()));
        await tester.pumpAndSettle();
        expect(
          find.text(l10n.t('harmonySharePeerUnavailable')),
          findsOneWidget,
        );
        expect(find.text(raw), findsNothing);
        final details = find.byTooltip(l10n.t('harmonyShareErrorDetails'));
        await tester.ensureVisible(details);
        // 服务可能在下一帧重建前清除错误，点击仍展示当前卡片绑定的快照。
        service.error = null;
        await tester.tap(details);
        await tester.pumpAndSettle();
        expect(find.text(raw), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(l10n.t('harmonyShareGotIt')));
        await tester.pumpAndSettle();
        expect(find.text(raw), findsNothing);

        final record = ShareTransferRecord(
          id: 'fixture',
          direction: ShareTransferDirection.send,
          status: ShareTransferStatus.failed,
          deviceName: 'fixture',
          address: '192.168.1.3',
          fileName: '',
          fileCount: 2,
          bytes: 5,
          createdAt: DateTime(2026),
          error: raw,
        );
        for (final batch in [false, true]) {
          await tester.pumpWidget(
            host(
              batch
                  ? HarmonyShareBatchDetails(
                      record: record,
                      files: Future.value(const []),
                    )
                  : HarmonyShareRecordDetailsDialog(record: record),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(raw), findsNothing);
          expect(
            find.textContaining(l10n.t('harmonySharePeerUnavailable')),
            findsOneWidget,
          );
          await tester.tap(find.text(l10n.t('harmonyShareErrorDetails')));
          await tester.pumpAndSettle();
          expect(find.text(raw), findsOneWidget);
          await tester.tap(find.text(l10n.t('harmonyShareGotIt')).last);
          await tester.pumpAndSettle();
          expect(find.text(raw), findsNothing);
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        expect(record.error, raw);
      });
    }
  }
}
