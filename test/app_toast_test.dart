import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/app_toast.dart';
import 'package:any_deck/features/widgets/dashboard_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppToast 与 DashboardSnack 统一在顶部居中渲染', (tester) async {
    final contextKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(body: SizedBox(key: contextKey)),
      ),
    );

    AppToast.show(contextKey.currentContext!, '统一提示');
    await tester.pump();

    var align = tester.widget<Align>(find.byKey(const Key('appToast')));
    expect(align.alignment, Alignment.topCenter);
    expect(find.text('统一提示'), findsOneWidget);

    DashboardSnack.show(contextKey.currentContext!, '兼容提示', isError: true);
    await tester.pump();

    align = tester.widget<Align>(find.byKey(const Key('appToast')));
    expect(align.alignment, Alignment.topCenter);
    expect(find.text('统一提示'), findsNothing);
    expect(find.text('兼容提示'), findsOneWidget);

    AppToast.dismiss();
    await tester.pump();
    expect(find.byKey(const Key('appToast')), findsNothing);
  });
}
