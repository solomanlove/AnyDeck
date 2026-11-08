import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/l10n/tables/app_l10n_settings.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/overview/settings/settings_item.dart';
import 'package:any_deck/features/overview/settings/settings_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只替换设置业务控件，检验真实导航、搜索定位和滚动恢复。
Widget _harness(String language, Brightness brightness) => MaterialApp(
  locale: Locale(language),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildAppTheme(brightness),
  home: Scaffold(
    body: Builder(
      builder: (context) => SettingsWorkspace(
        cardBuilder: (title, children) =>
            Card(child: Column(children: [Text(title), ...children])),
        items: [
          for (final category in SettingsCategory.values)
            SettingsItem(
              id: category.name,
              category: category,
              section: context.l10n.t(category.labelKey),
              title: '${category.name} setting',
              child: SizedBox(
                height: 800,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text('${category.name} control'),
                ),
              ),
            ),
          const SettingsItem(
            id: 'sound',
            category: SettingsCategory.mirroring,
            section: 'Audio',
            title: 'Audio forwarding',
            description: 'Forward device audio to host speakers',
            keywords: '声音 音量 sound volume',
            child: SizedBox(
              height: 80,
              child: Text('Audio forwarding control'),
            ),
          ),
          const SettingsItem(
            id: 'shortcut-action',
            category: SettingsCategory.shortcuts,
            section: 'Actions',
            title: 'Keyboard shortcuts',
            searchLabels: ['Take screenshot'],
            searchAliases: {'⌘⌥S': 'Take screenshot'},
            child: Column(
              children: [
                SizedBox(height: 1200),
                Text('Take screenshot'),
                SizedBox(height: 200),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('多空格动作搜索仍定位到快捷键具体行', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_harness('en', Brightness.light));
    await tester.enterText(
      find.byKey(const ValueKey('settings-search')),
      'Take   screenshot',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('settings-result-shortcut-action')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Take screenshot').hitTestable(), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('settings-search')),
      '⌘⌥S',
    );
    await tester.pumpAndSettle();
    expect(find.text('Take screenshot'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('settings-result-shortcut-action')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Take screenshot').hitTestable(), findsOneWidget);
  });

  test('搜索忽略大小写、支持多词与描述，新增文案中英文完整', () {
    const item = SettingsItem(
      id: 'audio',
      category: SettingsCategory.mirroring,
      section: 'Audio',
      title: 'Forwarding',
      description: 'host speakers',
      keywords: '声音 sound',
      child: SizedBox(),
    );
    expect(item.matches('  SOUND   host ', 'Mirroring'), isTrue);
    expect(item.matches('声音', 'Mirroring'), isTrue);
    expect(item.matches('sound missing', 'Mirroring'), isFalse);
    for (final key in settingsZh.keys.where(
      (key) => key.startsWith('settings'),
    )) {
      expect(settingsEn[key], isNotNull, reason: key);
    }
    expect(SettingsCategory.values, hasLength(7));
  });

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('七类导航、搜索定位、清除与空结果 $language $brightness', (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_harness(language, brightness));
        for (final category in SettingsCategory.values) {
          await tester.tap(
            find.byKey(ValueKey('settings-nav-${category.name}')),
          );
          await tester.pumpAndSettle();
          expect(find.text('${category.name} control'), findsOneWidget);
        }
        final search = find.byKey(const ValueKey('settings-search'));
        await tester.enterText(search, '声音');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('settings-result-sound')),
          findsOneWidget,
        );
        expect(find.text('about control'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('settings-result-sound')));
        await tester.pumpAndSettle();
        expect(
          find.text('Audio forwarding control').hitTestable(),
          findsOneWidget,
        );
        expect(tester.widget<TextField>(search).controller!.text, isEmpty);
        await tester.enterText(search, 'Take screenshot');
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('settings-result-shortcut-action')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Take screenshot').hitTestable(), findsOneWidget);
        await tester.enterText(search, 'not-existing-setting');
        await tester.pumpAndSettle();
        expect(
          find.text(
            language == 'zh'
                ? '未找到匹配的设置，请尝试其他关键词'
                : 'No matching settings. Try another keyword.',
          ),
          findsOneWidget,
        );
        await tester.tap(
          find.byTooltip(language == 'zh' ? '清除搜索' : 'Clear search'),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('settings-content-shortcuts')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('分类独立保留滚动位置，宽窄切换与下拉导航保留状态', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_harness('en', Brightness.light));
    final general = find.byKey(const ValueKey('settings-content-general'));
    await tester.drag(general, const Offset(0, -180));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('general control')).dy;
    await tester.enterText(
      find.byKey(const ValueKey('settings-search')),
      'no-match',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('general control')).dy, before);
    await tester.tap(find.byKey(const ValueKey('settings-nav-receivers')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-nav-general')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('general control')).dy, before);
    tester.view.physicalSize = const Size(420, 800);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-category-navigation')),
      findsNothing,
    );
    await tester.tap(find.byType(DropdownButtonFormField<SettingsCategory>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cast receiving').last);
    await tester.pumpAndSettle();
    expect(find.text('receivers control'), findsOneWidget);
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-category-navigation')),
      findsOneWidget,
    );
    expect(find.text('receivers control'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
