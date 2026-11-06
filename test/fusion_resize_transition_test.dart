import 'package:any_deck/app/window/mirror/widget/fusion_resize_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('等待副屏重排时显示图标，完成后隐藏', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FusionResizeTransition(
          resizing: true,
          child: ColoredBox(color: Colors.blue),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FusionResizeTransition(
          resizing: false,
          child: ColoredBox(color: Colors.blue),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 180));
    final opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(opacity.opacity, 0);
  });
}
