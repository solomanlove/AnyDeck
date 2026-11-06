import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/window/mirror/mirror_whiteboard_controls.dart';
import 'package:any_deck/features/control/whiteboard/mirror_whiteboard_canvas.dart';
import 'package:any_deck/features/control/whiteboard/mirror_whiteboard_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('白板一笔对应一次撤销，旋转清空旧坐标，轨迹容量有上限', () {
    final controller = MirrorWhiteboardController()..toggle();
    addTearDown(controller.dispose);
    controller.updateVideoOrientation(1080, 1920);
    controller.begin(1, const Offset(-0.2, 0.5));
    controller.update(1, const Offset(1.2, 0.8));
    controller.end(1);
    expect(controller.strokes.single.points, [
      const Offset(0, 0.5),
      const Offset(1, 0.8),
    ]);
    controller.undo();
    expect(controller.strokes, isEmpty);
    controller.begin(2, const Offset(0.2, 0.2));
    controller.setColor(Colors.blue);
    controller.end(2);
    expect(controller.strokes.single.color, Colors.green);
    controller.updateVideoOrientation(1920, 1080);
    expect(controller.strokes, isEmpty);
    controller.begin(3, const Offset(0.5, 0.5));
    for (var i = 0; i < 2500; i++) {
      controller.update(3, Offset(i.isEven ? 0 : 1, 0.5));
    }
    controller.end(3);
    expect(
      controller.strokes.single.points.length,
      lessThanOrEqualTo(MirrorWhiteboardController.maxPointsPerStroke),
    );
    controller.clear();
    for (var i = 0; i < MirrorWhiteboardController.maxStrokes + 1; i++) {
      controller.begin(i, const Offset(0.5, 0.5));
      controller.end(i);
    }
    expect(
      controller.strokes,
      hasLength(MirrorWhiteboardController.maxStrokes),
    );
    controller.clear();
    expect(controller.canUndo, isFalse);
  });

  testWidgets('白板只在开启后截获画面点击，并提供颜色撤销清空', (tester) async {
    final controller = MirrorWhiteboardController();
    addTearDown(controller.dispose);
    var deviceClicks = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 200,
                height: 300,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) => deviceClicks++,
                    ),
                    MirrorWhiteboardCanvas(controller: controller),
                  ],
                ),
              ),
              MirrorWhiteboardControls(controller: controller),
            ],
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(100, 100));
    expect(deviceClicks, 1);
    await tester.tap(find.byKey(const ValueKey('mirror-whiteboard-toggle')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('mirror-whiteboard-color')),
      findsOneWidget,
    );
    final gesture = await tester.startGesture(const Offset(100, 100));
    await gesture.moveTo(const Offset(150, 150));
    await gesture.up();
    await tester.pump();
    expect(deviceClicks, 1);
    expect(controller.strokes, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('mirror-whiteboard-color')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('蓝色').last);
    await tester.pumpAndSettle();
    expect(controller.color, Colors.blue);
    await tester.tap(find.byKey(const ValueKey('mirror-whiteboard-undo')));
    await tester.pump();
    expect(controller.strokes, isEmpty);
    controller.begin(10, const Offset(0.5, 0.5));
    controller.end(10);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mirror-whiteboard-clear')));
    await tester.pump();
    expect(controller.strokes, isEmpty);
    await tester.tap(find.byKey(const ValueKey('mirror-whiteboard-toggle')));
    await tester.pump();
    await tester.tapAt(const Offset(100, 100));
    expect(deviceClicks, 2);
  });
}
