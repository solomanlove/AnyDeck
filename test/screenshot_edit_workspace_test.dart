import 'dart:ui' as ui;

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/features/screenshot/editor/model/screenshot_edit.dart';
import 'package:any_deck/features/screenshot/editor/widgets/screenshot_edit_overlay.dart';
import 'package:any_deck/features/screenshot/editor/widgets/screenshot_edit_workspace.dart';
import 'package:any_deck/features/screenshot/model/screenshot_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用真实鼠标与 PNG 合成验证编辑工作区的退出和完成路径。
Future<ui.Image> _source(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.white, BlendMode.src);
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(120, 80);
      } finally {
        picture.dispose();
      }
    }))!;

Widget _app(
  ui.Image source, {
  required ValueChanged<ScreenshotEditResult> onDone,
  required VoidCallback onCancel,
  VoidCallback? onAbandon,
}) => ProviderScope(
  child: MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ScreenshotEditWorkspace(
        source: source,
        screenshotState: ScreenshotLayoutState(
          decodedImage: source,
          imgWidth: source.width,
          imgHeight: source.height,
        ),
        onDone: onDone,
        onCancel: onCancel,
        onAbandon: onAbandon,
      ),
    ),
  ),
);

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 40 && !ready(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(ready(), isTrue);
}

Future<void> _drawRectangle(WidgetTester tester) async {
  final overlay = tester.renderObject<RenderBox>(
    find.byType(ScreenshotEditOverlay),
  );
  final gesture = await tester.startGesture(
    overlay.localToGlobal(const Offset(10, 10)),
    kind: ui.PointerDeviceKind.mouse,
  );
  await gesture.moveTo(overlay.localToGlobal(const Offset(70, 50)));
  await gesture.up();
  await tester.pump();
}

void main() {
  testWidgets('工作区销毁时退出编辑会话并安全释放异步准备资源', (tester) async {
    final image = await _source(tester);
    addTearDown(image.dispose);
    var abandonments = 0;
    await tester.pumpWidget(
      _app(
        image,
        onDone: (result) => result.image.dispose(),
        onCancel: () {},
        onAbandon: () => abandonments++,
      ),
    );
    // 不等马赛克准备完成，模拟编辑期间切走页面或设备。
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(abandonments, 1);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('鼠标画图后取消可继续或确认放弃', (tester) async {
    final image = await _source(tester);
    addTearDown(image.dispose);
    var cancellations = 0;
    await tester.pumpWidget(
      _app(
        image,
        onDone: (result) => result.image.dispose(),
        onCancel: () => cancellations++,
      ),
    );
    await _until(
      tester,
      () =>
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('screenshotEditDone')),
              )
              .onPressed !=
          null,
    );
    await _drawRectangle(tester);
    await tester.tap(find.byKey(const ValueKey('screenshotEditCancel')));
    await tester.pumpAndSettle();
    expect(find.text('放弃本次编辑？'), findsOne);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(cancellations, 0);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byKey(const ValueKey('screenshotEditCancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃编辑'));
    await tester.pumpAndSettle();
    expect(cancellations, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('完成合成保留原图尺寸且写入矩形像素', (tester) async {
    final image = await _source(tester);
    addTearDown(image.dispose);
    ScreenshotEditResult? result;
    await tester.pumpWidget(
      _app(image, onDone: (value) => result = value, onCancel: () {}),
    );
    await _until(
      tester,
      () =>
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('screenshotEditDone')),
              )
              .onPressed !=
          null,
    );
    await _drawRectangle(tester);
    await tester.tap(find.byKey(const ValueKey('screenshotEditDone')));
    await tester.pump();
    await _until(tester, () => result != null);
    addTearDown(() => result!.image.dispose());
    expect(result!.image.width, 120);
    expect(result!.image.height, 80);
    expect(result!.bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final pixels = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(result!.bytes);
      try {
        final decoded = (await codec.getNextFrame()).image;
        try {
          expect(decoded.width, 120);
          expect(decoded.height, 80);
          return await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
        } finally {
          decoded.dispose();
        }
      } finally {
        codec.dispose();
      }
    });
    final edge = (10 * 120 + 30) * 4;
    expect(pixels!.getUint8(edge), Colors.red.r * 255);
    expect(pixels.getUint8(edge + 1), closeTo(Colors.red.g * 255, 1));
    final inside = (30 * 120 + 30) * 4;
    expect(pixels.getUint8(inside), 255);
    expect(pixels.getUint8(inside + 1), 255);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
