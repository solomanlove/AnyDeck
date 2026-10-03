import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/process/host_platform_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/feedback/model/github_feedback.dart';
import 'package:any_deck/features/feedback/widget/github_feedback_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 替代真实浏览器启动，验证等待、失败和复制流程，不访问网络。
class _FakeHost extends HostPlatformService {
  final result = Completer<bool>();
  final opened = <Uri>[];

  @override
  Future<bool> openWebUri(Uri uri) {
    opened.add(uri);
    return result.future;
  }
}

void main() {
  test(
    'issue URL preserves Unicode and reserved characters without extra keys',
    () {
      const body = '中文 & # ? % +\nhttps://example.com/?a=1&b=2';
      final uri = GithubFeedback.newIssueUri(FeedbackKind.bug, body);
      final decoded = Uri.parse(uri.toString());
      expect(decoded.host, 'github.com');
      expect(decoded.path, '/solomanlove/AnyDeck/issues/new');
      expect(decoded.queryParameters, {'title': '[Bug] ', 'body': body});
      expect(decoded.fragment, isEmpty);
    },
  );

  test('localized drafts remain short and do not require remote templates', () {
    for (final locale in AppLocalizations.supportedLocales) {
      for (final kind in FeedbackKind.values) {
        final body = GithubFeedback.body(
          AppLocalizations(locale),
          kind,
          'macos',
        );
        final uri = GithubFeedback.newIssueUri(kind, body);
        expect(body, contains('macos'));
        expect(body, isNot(contains('{system}')));
        expect(uri.toString().length, lessThan(7000));
        expect(uri.queryParameters.keys, unorderedEquals(['title', 'body']));
      }
    }
  });

  test(
    'browser helper rejects non-web links without launching a process',
    () async {
      final host = HostPlatformService();
      expect(await host.openWebUri(Uri.parse('file:///tmp/feedback')), isFalse);
      expect(await host.openWebUri(Uri.parse('javascript:alert(1)')), isFalse);
      expect(await host.openWebUri(Uri.parse('https:/missing-host')), isFalse);
    },
  );

  for (final language in ['zh', 'en']) {
    testWidgets('$language: blocks duplicate opens and copies failed target', (
      tester,
    ) async {
      final host = _FakeHost();
      final l10n = AppLocalizations(Locale(language));
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [hostPlatformServiceProvider.overrideWithValue(host)],
          child: MaterialApp(
            locale: Locale(language),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: language == 'zh' ? ThemeData.light() : ThemeData.dark(),
            home: const Scaffold(body: GithubFeedbackDialog()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.t('feedbackFeature')));
      await tester.pump();
      await tester.tap(find.text(l10n.t('feedbackOpenGithub')));
      await tester.pump();
      expect(host.opened.single.queryParameters['title'], '[Feature] ');
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      host.result.complete(false);
      await tester.pumpAndSettle();
      expect(find.text(l10n.t('feedbackOpenFailed')), findsOneWidget);
      await tester.tap(find.text(l10n.t('feedbackCopyLink')));
      await tester.pumpAndSettle();
      expect(clipboard, host.opened.single.toString());
      expect(find.text(l10n.t('feedbackLinkCopied')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
