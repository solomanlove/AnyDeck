import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/screenshot/editor/model/screenshot_edit.dart';
import 'package:any_deck/features/screenshot/editor/widgets/screenshot_edit_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用独立工具栏验证窄窗口、本地化和导出过程中的交互锁定。
Widget _app({
  required Locale locale,
  required Brightness brightness,
  bool busy = false,
  bool mosaicAvailable = true,
  ScreenshotEditState? state,
  ValueChanged<ScreenshotEditTool>? onToolChanged,
  ValueChanged<double>? onWidthChanged,
  VoidCallback? onDone,
  VoidCallback? onCancel,
}) => MaterialApp(
  locale: locale,
  theme: buildAppTheme(brightness),
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: ScreenshotEditToolbar(
        state: state ?? ScreenshotEditState(),
        busy: busy,
        mosaicAvailable: mosaicAvailable,
        onToolChanged: onToolChanged ?? (_) {},
        onColorChanged: (_) {},
        onWidthChanged: onWidthChanged ?? (_) {},
        onUndo: () {},
        onRedo: () {},
        onClear: () {},
        onCancel: onCancel ?? () {},
        onDone: onDone ?? () {},
      ),
    ),
  ),
);

void main() {
  for (final locale in const [Locale('zh'), Locale('en')]) {
    for (final brightness in Brightness.values) {
      testWidgets('窄窗口 ${locale.languageCode} $brightness 固定显示完成和取消', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var completed = false;
        var cancelled = false;
        await tester.pumpWidget(
          _app(
            locale: locale,
            brightness: brightness,
            onDone: () => completed = true,
            onCancel: () => cancelled = true,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          find.text(locale.languageCode == 'zh' ? '完成' : 'Done'),
          findsOne,
        );
        await tester.tap(find.byKey(const ValueKey('screenshotEditDone')));
        await tester.tap(find.byKey(const ValueKey('screenshotEditCancel')));
        expect(completed, isTrue);
        expect(cancelled, isTrue);
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('screenshotEditUndo')),
              )
              .onPressed,
          isNull,
        );
      });
    }
  }

  testWidgets('工具和原图像素宽度通过回调更新', (tester) async {
    tester.view.physicalSize = const Size(1500, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ScreenshotEditTool? selected;
    double? selectedWidth;
    await tester.pumpWidget(
      _app(
        locale: const Locale('zh'),
        brightness: Brightness.light,
        onToolChanged: (tool) => selected = tool,
        onWidthChanged: (width) => selectedWidth = width,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('screenshotEditToolmosaic')));
    expect(selected, ScreenshotEditTool.mosaic);
    await tester.tap(find.byKey(const ValueKey('screenshotEditWidth')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('48 px'));
    await tester.pumpAndSettle();
    expect(selectedWidth, 48);
    expect(tester.takeException(), isNull);
  });

  testWidgets('导出中全部修改与退出操作禁用', (tester) async {
    final mark = ScreenshotEditMark(
      tool: ScreenshotEditTool.pen,
      points: const [Offset.zero, Offset(20, 20)],
      color: Colors.red,
      width: 6,
    );
    await tester.pumpWidget(
      _app(
        locale: const Locale('en'),
        brightness: Brightness.dark,
        busy: true,
        state: ScreenshotEditState(marks: [mark], redoMarks: [mark]),
      ),
    );
    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(button.onPressed, isNull);
    }
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<PopupMenuButton<double>>(
            find.byKey(const ValueKey('screenshotEditWidth')),
          )
          .enabled,
      isFalse,
    );
    for (final ink in tester.widgetList<InkWell>(find.byType(InkWell))) {
      expect(ink.onTap, isNull);
    }
    expect(find.byType(CircularProgressIndicator), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('马赛克资源不可用时仅禁用马赛克工具', (tester) async {
    await tester.pumpWidget(
      _app(
        locale: const Locale('zh'),
        brightness: Brightness.light,
        mosaicAvailable: false,
      ),
    );
    for (final tool in ScreenshotEditTool.values) {
      final button = tester.widget<IconButton>(
        find.byKey(ValueKey('screenshotEditTool${tool.name}')),
      );
      expect(button.onPressed == null, tool == ScreenshotEditTool.mosaic);
    }
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
}
