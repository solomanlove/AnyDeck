import 'dart:io';
import 'dart:ui' as ui;

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/devices/model/device_workspace_view_state.dart';
import 'package:any_deck/features/devices/widgets/device_list_filters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/search_field_expectations.dart';

/// 工具栏验证使用真实主题和文本布局，不启动设备发现或桌面 App。
void main() {
  for (final locale in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('工具栏 $locale ${brightness.name} 单行和窄屏均无溢出', (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final boundary = GlobalKey();
        await _loadCaptureFonts(tester);
        for (final size in [
          (width: 1200.0, scale: 1.0),
          (width: 920.0, scale: 1.0),
          (width: 720.0, scale: 1.0),
          (width: 360.0, scale: 1.0),
          (width: 320.0, scale: 1.6),
          (width: 560.0, scale: 1.6),
        ]) {
          tester.view.physicalSize = Size(size.width, 700);
          await tester.pumpWidget(
            _host(
              locale: locale,
              brightness: brightness,
              textScale: size.scale,
              child: RepaintBoundary(
                key: boundary,
                child: DeviceListFilters(
                  controller: controller,
                  onlineCount: 2,
                  totalCount: 6,
                  filter: DeviceStatusFilter.all,
                  onFilterChanged: (_) {},
                  viewMode: DeviceViewMode.wall,
                  onViewModeChanged: (_) {},
                  batchMode: true,
                  onBatchModeChanged: (_) {},
                  onSearchChanged: (_) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final theme = Theme.of(tester.element(find.byType(DeviceListFilters)));
          for (final key in [
            'deviceFilter-all',
            'deviceView-wall',
            'deviceBatchManage',
          ]) {
            final button = tester.widget<ButtonStyleButton>(find.byKey(Key(key)));
            expect(
              button.style!.foregroundColor!.resolve({}),
              theme.colorScheme.onSurface,
            );
            expect(
              button.style!.backgroundColor!.resolve({}),
              theme.deviceSelectionBackground,
            );
          }
          for (final key in [
            'deviceFilter-online',
            'deviceFilter-offline',
            'deviceView-list',
          ]) {
            final button = tester.widget<TextButton>(find.byKey(Key(key)));
            expect(
              button.style!.foregroundColor!.resolve({}),
              theme.colorScheme.onSurfaceVariant,
            );
            expect(button.style!.backgroundColor!.resolve({}), Colors.transparent);
          }
          expectSearchFieldRadius(
            tester,
            find.byType(TextField),
            radius: AppThemeSizes.radiusMedium,
          );
          for (final key in [
            'deviceFilter-all',
            'deviceFilter-online',
            'deviceFilter-offline',
            'deviceListSearch',
            'deviceView-wall',
            'deviceView-list',
            'deviceBatchManage',
          ]) {
            final rect = tester.getRect(find.byKey(Key(key)));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
          }
          final search = tester.getRect(
            find.byKey(const Key('deviceListSearch')),
          );
          expect(search.height, size.scale == 1 ? 36 : greaterThan(36));
          final manage = tester.getRect(
            find.byKey(const Key('deviceBatchManage')),
          );
          if (size.width >= 920) {
            expect(search.center.dy, closeTo(manage.center.dy, 2));
            expect(search.width, greaterThan(240));
            expect(tester.getSize(find.byType(DeviceListFilters)).height, 46);
            expect(manage.height, 36);
            expect(
              tester.getSize(find.byKey(const Key('deviceFilter-all'))).height,
              36,
            );
          } else if (size.width == 360) {
            expect(search.top, greaterThan(manage.bottom));
            expect(search.width, size.width);
          }
          await _capture(
            tester,
            boundary,
            '$locale-${brightness.name}-${size.width.toInt()}',
          );
        }
      });
    }
  }

  testWidgets('视图、筛选和批量切换各自生效并保留搜索内容', (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final queries = <String>[];
    var filter = DeviceStatusFilter.all;
    var view = DeviceViewMode.wall;
    var batchMode = false;
    await tester.pumpWidget(
      _host(
        child: StatefulBuilder(
          builder: (context, setState) => DeviceListFilters(
            controller: controller,
            onlineCount: 2,
            totalCount: 6,
            filter: filter,
            onFilterChanged: (value) => setState(() => filter = value),
            viewMode: view,
            onViewModeChanged: (value) => setState(() => view = value),
            batchMode: batchMode,
            onBatchModeChanged: (value) => setState(() => batchMode = value),
            onSearchChanged: queries.add,
          ),
        ),
      ),
    );
    final search = find.byKey(const Key('deviceListSearch'));
    expect(find.byType(Checkbox), findsNothing);
    await tester.enterText(search, 'Xiaomi');
    await tester.pumpAndSettle();
    expectSearchFieldRadius(
      tester,
      search,
      focused: true,
      radius: AppThemeSizes.radiusMedium,
    );
    expect(queries, ['Xiaomi']);
    expect(tester.getSize(search).height, 36);
    final initialWidth = tester.getSize(search).width;
    await tester.tap(find.byKey(const Key('deviceView-list')));
    await tester.tap(find.byKey(const Key('deviceFilter-offline')));
    await tester.tap(find.byKey(const Key('deviceBatchManage')));
    await tester.pumpAndSettle();
    expect(view, DeviceViewMode.list);
    expect(filter, DeviceStatusFilter.offline);
    expect(batchMode, isTrue);
    expect(controller.text, 'Xiaomi');
    expect(find.text('退出批量管理'), findsOneWidget);
    expect(tester.getSize(search).width, lessThan(initialWidth));
    await tester.tap(find.byKey(const Key('deviceBatchManage')));
    await tester.pumpAndSettle();
    expect(batchMode, isFalse);
    final manage = tester.widget<OutlinedButton>(
      find.byKey(const Key('deviceBatchManage')),
    );
    final theme = Theme.of(tester.element(find.byType(DeviceListFilters)));
    expect(
      manage.style!.backgroundColor!.resolve({}),
      theme.appColors.panelSurface,
    );
    expect(
      manage.style!.side!.resolve({})!.color,
      theme.colorScheme.outlineVariant,
    );
    expect(tester.getSize(search).width, closeTo(initialWidth, 0.1));
    await tester.tap(find.byTooltip('清空'));
    await tester.pumpAndSettle();
    expect(queries, ['Xiaomi', '']);
    expect(controller.text, isEmpty);
    expect(filter, DeviceStatusFilter.offline);
    expect(view, DeviceViewMode.list);
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索框随窗口伸缩而占据中间剩余空间', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var previousWidth = 0.0;
    for (final width in [1000.0, 1200.0]) {
      tester.view.physicalSize = Size(width, 700);
      await tester.pumpWidget(
        _host(
          child: DeviceListFilters(
            controller: controller,
            onlineCount: 2,
            totalCount: 6,
            filter: DeviceStatusFilter.all,
            onFilterChanged: (_) {},
            viewMode: DeviceViewMode.wall,
            onViewModeChanged: (_) {},
            batchMode: false,
            onBatchModeChanged: (_) {},
            onSearchChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final currentWidth = tester
          .getSize(find.byKey(const Key('deviceListSearch')))
          .width;
      if (previousWidth > 0) {
        expect(currentWidth - previousWidth, closeTo(200, 0.1));
      }
      previousWidth = currentWidth;
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('收紧留白后760px英文工具栏仍优先单行并保留搜索空间', (tester) async {
    tester.view.physicalSize = const Size(760, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        locale: 'en',
        child: DeviceListFilters(
          controller: controller,
          onlineCount: 2,
          totalCount: 6,
          filter: DeviceStatusFilter.all,
          onFilterChanged: (_) {},
          viewMode: DeviceViewMode.wall,
          onViewModeChanged: (_) {},
          batchMode: false,
          onBatchModeChanged: (_) {},
          onSearchChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deviceToolbarSingleRow')), findsOneWidget);
    final search = tester.getRect(find.byKey(const Key('deviceListSearch')));
    final manage = tester.getRect(find.byKey(const Key('deviceBatchManage')));
    expect(search.width, greaterThanOrEqualTo(160));
    expect(search.center.dy, manage.center.dy);
    expect(tester.takeException(), isNull);
  });
}

Widget _host({
  required Widget child,
  String locale = 'zh',
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) {
  const font = String.fromEnvironment('DEVICE_FILTER_CAPTURE_FONT');
  final theme = buildAppTheme(brightness);
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme.copyWith(
      textTheme: theme.textTheme.apply(
        fontFamily: font.isEmpty ? null : 'CaptureFont',
      ),
    ),
    locale: Locale(locale),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    builder: (context, content) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: content!,
    ),
    home: Scaffold(
      body: Align(alignment: Alignment.topCenter, child: child),
    ),
  );
}

/// 字体与导出目录通过 dart-define 注入，普通测试不依赖本机路径。
Future<void> _loadCaptureFonts(WidgetTester tester) async {
  const font = String.fromEnvironment('DEVICE_FILTER_CAPTURE_FONT');
  if (font.isEmpty) return;
  await tester.runAsync(() async {
    final loader = FontLoader('CaptureFont')
      ..addFont(File(font).readAsBytes().then(ByteData.sublistView));
    await loader.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  const output = String.fromEnvironment('DEVICE_FILTER_CAPTURE_DIR');
  if (output.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}
