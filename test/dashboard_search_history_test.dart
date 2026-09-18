import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/widget/dashboard_history_text_field.dart';
import 'package:any_deck/app/widget/dashboard_tab_layout.dart';
import 'package:any_deck/core/search/dashboard_search_history_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('应用历史沿用旧 key，进程与文件历史独立持久化并去重', () async {
    SharedPreferences.setMockInitialValues({
      'apps_search_history': ['旧记录'],
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(await container.read(appsSearchHistoryProvider.future), ['旧记录']);
    expect(
      await container.read(processesSearchHistoryProvider.future),
      isEmpty,
    );
    expect(await container.read(filesSearchHistoryProvider.future), isEmpty);

    final processes = container.read(processesSearchHistoryProvider.notifier);
    await processes.add('  adb  ');
    await processes.add('top');
    await processes.add('adb');
    expect(container.read(processesSearchHistoryProvider).value, [
      'adb',
      'top',
    ]);
    await container.read(filesSearchHistoryProvider.notifier).add('Download');
    expect(container.read(filesSearchHistoryProvider).value, ['Download']);
    expect(container.read(appsSearchHistoryProvider).value, ['旧记录']);

    await processes.remove('top');
    final reloaded = ProviderContainer();
    addTearDown(reloaded.dispose);
    expect(await reloaded.read(processesSearchHistoryProvider.future), ['adb']);
    expect(await reloaded.read(filesSearchHistoryProvider.future), [
      'Download',
    ]);
    await processes.clear();
    expect(container.read(processesSearchHistoryProvider).value, isEmpty);
  });

  testWidgets('筛选历史下拉保留 DEBUG 固定选项并可选择历史', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? selected;
    String? changed;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [AppLocalizationsDelegate()],
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: DashboardHistoryTextField(
                controller: controller,
                hintText: '筛选',
                history: const ['AirController'],
                defaultOptions: const [
                  DashboardHistoryOption(value: 'debug', label: '筛选 DEBUG 应用'),
                ],
                onChanged: (value) => changed = value,
                onSubmitted: (_) {},
                onSelected: (value) => selected = value,
                onHistoryRemoved: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('筛选 DEBUG 应用'), findsOneWidget);
    expect(find.text('AirController'), findsOneWidget);

    await tester.tap(find.text('筛选 DEBUG 应用'));
    await tester.pumpAndSettle();
    expect(controller.text, 'debug');
    expect(changed, 'debug');
    expect(selected, 'debug');

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AirController'));
    await tester.pumpAndSettle();
    expect(controller.text, 'AirController');
    expect(selected, 'AirController');
  });

  testWidgets('窄筛选框展开历史时列表项不溢出', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [AppLocalizationsDelegate()],
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 90,
              child: DashboardHistoryTextField(
                controller: controller,
                hintText: '筛选',
                history: const ['com.example.long.package.name'],
                onChanged: (_) {},
                onSubmitted: (_) {},
                onSelected: (_) {},
                onHistoryRemoved: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('com.example.long.package.name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('历史下拉展开时更新历史不会在 build 阶段重建 Overlay', (tester) async {
    final controller = TextEditingController();
    final history = ValueNotifier<List<String>>(['旧记录']);
    addTearDown(controller.dispose);
    addTearDown(history.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [AppLocalizationsDelegate()],
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: ValueListenableBuilder<List<String>>(
                valueListenable: history,
                builder: (context, items, _) => DashboardHistoryTextField(
                  controller: controller,
                  hintText: '筛选',
                  history: items,
                  onChanged: (_) {},
                  onSubmitted: (_) {},
                  onSelected: (_) {},
                  onHistoryRemoved: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    history.value = ['新记录'];
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('新记录'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('应用工具栏展开历史后仍只绘制一个筛选框且页面不溢出', (tester) async {
    final controller = TextEditingController();
    final history = ValueNotifier<List<String>>(['旧记录']);
    addTearDown(controller.dispose);
    addTearDown(history.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [AppLocalizationsDelegate()],
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 700,
            child: ValueListenableBuilder<List<String>>(
              valueListenable: history,
              builder: (context, items, _) => DashboardTabLayout(
                toolbar: DashboardSearchToolbar<int>(
                  searchController: controller,
                  searchHint: '筛选',
                  onSearchChanged: (_) {},
                  onSearchSubmitted: (_) {},
                  onSearchClear: controller.clear,
                  hasSearchQuery: false,
                  searchHistory: items,
                  onSearchHistorySelected: (_) {},
                  onSearchHistoryRemoved: (_) {},
                  searchDefaultOptions: const [
                    DashboardHistoryOption(value: 'debug', label: '筛选 DEBUG 应用'),
                  ],
                  segments: const {0: Text('用户应用'), 1: Text('全部')},
                  currentSegment: 1,
                  onSegmentChanged: (_) {},
                  trailingActions: const [Icon(Icons.refresh)],
                ),
                body: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    history.value = ['新记录'];
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();
    expect(find.text('新记录'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
