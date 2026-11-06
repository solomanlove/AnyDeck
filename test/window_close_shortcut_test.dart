import 'dart:io';

import 'package:any_deck/app/window/window_close_shortcut.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证设置页展示的标准窗口组合键确实调用已有窗口生命周期入口。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final calls = <String>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return call.method == 'isFullScreen' || call.method == 'isMinimized'
              ? false
              : null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets('子窗口关闭组合键只关闭当前窗口', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: WindowCloseShortcut(child: Text('window'))),
    );
    await tester.pump();
    await _shortcut(tester, LogicalKeyboardKey.keyW);
    expect(calls, ['close']);
  });

  testWidgets('主窗口显示按键使用配置，关闭和退出回调保持有效', (tester) async {
    var quits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MainWindowCloseShortcut(
          showWindowKey: '5',
          onQuit: () => quits++,
          child: const Text('main'),
        ),
      ),
    );
    await tester.pump();
    await _shortcut(tester, LogicalKeyboardKey.digit1);
    expect(calls, isEmpty);
    await _shortcut(tester, LogicalKeyboardKey.digit5);
    expect(calls, containsAllInOrder(['show', 'focus']));
    calls.clear();
    await _shortcut(tester, LogicalKeyboardKey.keyW);
    expect(calls, ['close']);
    if (Platform.isMacOS) {
      await _shortcut(tester, LogicalKeyboardKey.keyQ);
      expect(quits, 1);
    }
  });
}

Future<void> _shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  final modifier = Platform.isMacOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}
