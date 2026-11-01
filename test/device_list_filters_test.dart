import 'dart:io';
import 'dart:ui' as ui;

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/devices/widgets/device_list_filters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 使用真实 Theme 验证布局和交互；可选导出 Widget 图，不启动桌面 App。
void main() {
  for (final locale in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('筛选栏 $locale ${brightness.name} 适应窗口宽度和文字缩放', (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final boundary = GlobalKey();
        await _loadCaptureFonts(tester);

        for (final size in [
          (width: 920.0, scale: 1.0),
          (width: 720.0, scale: 1.0),
          (width: 360.0, scale: 1.0),
          (width: 560.0, scale: 1.6),
        ]) {
          tester.view.physicalSize = Size(size.width, 480);
          await tester.pumpWidget(
            _host(
              locale: locale,
              brightness: brightness,
              textScale: size.scale,
              child: RepaintBoundary(
                key: boundary,
                child: ColoredBox(
                  color: buildAppTheme(brightness).scaffoldBackgroundColor,
                  child: DeviceListFilters(
                    controller: controller,
                    onlineCount: 1,
                    totalCount: 13,
                    onlineOnly: false,
                    onOnlineOnlyChanged: (_) {},
                    onSearchChanged: (_) {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final key in [
            'deviceListCounts',
            'deviceListSearch',
            'deviceListOnlineOnly',
          ]) {
            final rect = tester.getRect(find.byKey(Key(key)));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
          }
          final search = tester.getRect(
            find.byKey(const Key('deviceListSearch')),
          );
          final filter = tester.getRect(
            find.byKey(const Key('deviceListOnlineOnly')),
          );
          if (size.width == 920) {
            expect(search.center.dy, closeTo(filter.center.dy, 1));
            expect(search.width, greaterThan(240));
          } else if (size.width == 360) {
            expect(filter.top, greaterThan(search.bottom));
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

  testWidgets('搜索清除按钮按内容出现，切换在线筛选与缩放保留输入', (tester) async {
    tester.view.physicalSize = const Size(920, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final queries = <String>[];
    var onlineOnly = false;
    await tester.pumpWidget(
      _host(
        child: StatefulBuilder(
          builder: (context, setState) => DeviceListFilters(
            controller: controller,
            onlineCount: 1,
            totalCount: 13,
            onlineOnly: onlineOnly,
            onOnlineOnlyChanged: (value) => setState(() => onlineOnly = value),
            onSearchChanged: queries.add,
          ),
        ),
      ),
    );
    expect(find.byTooltip('清空'), findsNothing);
    final search = find.byKey(const Key('deviceListSearch'));
    await tester.enterText(search, 'Xiaomi');
    await tester.pumpAndSettle();
    expect(queries, ['Xiaomi']);
    expect(find.byTooltip('清空'), findsOneWidget);
    await tester.tap(find.byKey(const Key('deviceListOnlineOnly')));
    await tester.pumpAndSettle();
    expect(onlineOnly, isTrue);
    expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, isTrue);
    tester.view.physicalSize = const Size(360, 480);
    await tester.pumpAndSettle();
    expect(controller.text, 'Xiaomi');
    expect(find.text('1 在线'), findsOneWidget);
    expect(find.text('12 离线/不可用'), findsOneWidget);
    await tester.tap(find.byTooltip('清空'));
    await tester.pumpAndSettle();
    expect(queries, ['Xiaomi', '']);
    expect(controller.text, isEmpty);
    expect(find.byTooltip('清空'), findsNothing);
    expect(onlineOnly, isTrue);
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
