import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/process/host_platform_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/feedback/controller/feedback_draft_controller.dart';
import 'package:any_deck/features/feedback/model/feedback_environment.dart';
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

const _environment = FeedbackEnvironment(
  hostSystem: 'macOS 26.0 (arm64)',
  appVersion: '2.3.4+56',
  deviceModel: 'Pixel 9',
  deviceSystem: 'Android 16 (API 36)',
  connectionKey: 'feedbackUsb',
);

void main() {
  test(
    'issue URL preserves Unicode and reserved characters without extra keys',
    () {
      const body = '中文 & # ? % +\nhttps://example.com/?a=1&b=2';
      final uri = GithubFeedback.newIssueUri(
        FeedbackKind.bug,
        body,
        title: '标题 & # ?',
      );
      final decoded = Uri.parse(uri.toString());
      expect(decoded.host, 'github.com');
      expect(decoded.path, '/solomanlove/AnyDeck/issues/new');
      expect(decoded.queryParameters, {
        'title': '[Bug] 标题 & # ?',
        'body': body,
      });
      expect(decoded.fragment, isEmpty);
    },
  );

  test('localized drafts remain short and do not require remote templates', () {
    for (final locale in AppLocalizations.supportedLocales) {
      for (final kind in FeedbackKind.values) {
        final body = GithubFeedback.body(
          AppLocalizations(locale),
          kind,
          _environment.format(AppLocalizations(locale)),
        );
        final uri = GithubFeedback.newIssueUri(kind, body);
        expect(body, contains('macOS 26.0 (arm64)'));
        expect(body, contains('2.3.4+56'));
        expect(body, contains('Pixel 9'));
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

  testWidgets(
    'long body is copied before opening; clipboard failure stops launch',
    (tester) async {
      final host = _FakeHost()..result.complete(true);
      const l10n = AppLocalizations(Locale('en'));
      var failCopy = true;
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            if (failCopy) {
              throw PlatformException(code: 'clipboard-unavailable');
            }
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
          overrides: [
            hostPlatformServiceProvider.overrideWithValue(host),
            feedbackEnvironmentProvider.overrideWithValue(_environment),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(body: GithubFeedbackDialog()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final body = List.filled(1500, '中文 & #\n').join();
      await tester.enterText(
        find.byKey(const ValueKey('feedbackTitleField')),
        'Long feedback',
      );
      await tester.enterText(
        find.byKey(const ValueKey('feedbackBodyField')),
        body,
      );
      await tester.pump();
      await tester.tap(find.text(l10n.t('feedbackOpenGithub')));
      await tester.pumpAndSettle();
      expect(host.opened, isEmpty);
      expect(find.text(l10n.t('feedbackCopyFailed')), findsOneWidget);
      failCopy = false;
      await tester.tap(find.text(l10n.t('feedbackOpenGithub')));
      await tester.pumpAndSettle();
      expect(clipboard, body);
      expect(host.opened.single.queryParameters['body'], isEmpty);
      expect(
        host.opened.single.queryParameters['title'],
        '[Bug] Long feedback',
      );
      expect(find.text(l10n.t('feedbackBodyCopiedOpen')), findsOneWidget);
      expect(tester.takeException(), isNull);
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
          overrides: [
            hostPlatformServiceProvider.overrideWithValue(host),
            feedbackEnvironmentProvider.overrideWithValue(_environment),
          ],
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
      Future<void> selectKind(String key) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final chip = find.widgetWithText(ChoiceChip, l10n.t(key));
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        await tester.tap(chip);
        await tester.pumpAndSettle();
      }

      final titleField = find.byKey(const ValueKey('feedbackTitleField'));
      final bodyField = find.byKey(const ValueKey('feedbackBodyField'));
      expect(
        tester.widget<TextField>(bodyField).controller!.text,
        contains('2.3.4+56'),
      );
      await tester.tap(find.text(l10n.t('feedbackOpenGithub')));
      await tester.pump();
      expect(host.opened, isEmpty);
      expect(
        tester.widget<TextField>(titleField).decoration!.errorText,
        l10n.t('feedbackTitleRequired'),
      );
      await tester.enterText(titleField, 'Bug 标题 & ?');
      await tester.enterText(bodyField, '已修改的正文 # &\n第二行');
      await selectKind('feedbackFeature');
      expect(tester.widget<TextField>(titleField).controller!.text, isEmpty);
      expect(
        tester.widget<TextField>(bodyField).controller!.text,
        contains('Pixel 9'),
      );
      await tester.enterText(titleField, 'Feature 标题');
      await tester.enterText(bodyField, '功能建议正文');
      await selectKind('feedbackBug');
      expect(
        tester.widget<TextField>(titleField).controller!.text,
        'Bug 标题 & ?',
      );
      expect(
        tester.widget<TextField>(bodyField).controller!.text,
        '已修改的正文 # &\n第二行',
      );
      await selectKind('feedbackFeature');
      await tester.tap(find.text(l10n.t('feedbackOpenGithub')));
      await tester.pump();
      expect(
        host.opened.single.queryParameters['title'],
        '[Feature] Feature 标题',
      );
      expect(host.opened.single.queryParameters['body'], '功能建议正文');
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
