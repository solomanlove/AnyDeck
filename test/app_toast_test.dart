import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/app_toast.dart';
import 'package:any_deck/features/widgets/dashboard_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(AppToast.dismiss);

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

  testWidgets('复制成功提示默认 1600ms 后自动消失', (tester) async {
    final context = await _pumpToastHost(tester);
    AppToast.show(context, '已复制到剪贴板');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1599));
    expect(find.text('已复制到剪贴板'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const Key('appToast')), findsNothing);
  });

  testWidgets('同一帧连续提示不会留下失去 Timer 的旧提示', (tester) async {
    final context = await _pumpToastHost(tester);
    AppToast.show(context, '已复制到剪贴板');
    DashboardSnack.show(context, '最新提示');
    await tester.pump();
    expect(find.text('已复制到剪贴板'), findsNothing);
    expect(find.text('最新提示'), findsOneWidget);
    expect(find.byKey(const Key('appToast')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('appToast')), findsNothing);
  });

  testWidgets('首帧绘制前主动关闭不会让提示在下一帧重新出现', (tester) async {
    final context = await _pumpToastHost(tester);
    AppToast.show(context, '已复制到剪贴板');
    AppToast.dismiss();
    AppToast.dismiss();
    await tester.pump();
    expect(find.byKey(const Key('appToast')), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('appToast')), findsNothing);
  });

  testWidgets('提示被不透明弹层卸载时到期也必须移除，不能在弹层关闭后复现', (tester) async {
    final context = await _pumpToastHost(tester);
    AppToast.show(context, '已复制到剪贴板');
    await tester.pump();
    final cover = OverlayEntry(
      opaque: true,
      builder: (_) => const SizedBox.expand(),
    );
    Overlay.of(context, rootOverlay: true).insert(cover);
    await tester.pump();
    expect(find.text('已复制到剪贴板'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    cover
      ..remove()
      ..dispose();
    await tester.pump();
    expect(find.byKey(const Key('appToast')), findsNothing);
  });

  testWidgets('重复触发重新计时，旧截止时间不会提前关闭新提示', (tester) async {
    final context = await _pumpToastHost(tester);
    AppToast.show(context, '第一次复制');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    AppToast.show(context, '第二次复制');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('第二次复制'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.byKey(const Key('appToast')), findsNothing);
  });

  testWidgets('窗口 Overlay 销毁后到期清理不会抛异常或污染下一窗口', (tester) async {
    final context = await _pumpToastHost(tester);
    AppToast.show(context, '旧窗口提示');
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    final newContext = await _pumpToastHost(tester);
    AppToast.show(newContext, '新窗口提示');
    await tester.pump();
    expect(find.text('新窗口提示'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('appToast')), findsNothing);
  });
}

/// 为公共轻提示提供独立根 Overlay，模拟投屏子窗口的渲染宿主。
Future<BuildContext> _pumpToastHost(WidgetTester tester) async {
  final contextKey = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(body: SizedBox(key: contextKey)),
    ),
  );
  return contextKey.currentContext!;
}
