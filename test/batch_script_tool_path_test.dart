import 'package:any_deck/core/adb/adb_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_context_menu_fixture.dart';

/// 批量脚本必须经统一 HDC 服务执行，由服务处理自定义路径与原生回退。
class _BatchHdc extends DeviceMenuHdc {
  @override
  String get executable => '/custom/tools/hdc';

  final commands = <(String, String)>[];

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add((deviceId, command));
    return const AdbResult(
      exitCode: 0,
      stdout: 'custom-hdc-result',
      stderr: '',
    );
  }
}

void main() {
  testWidgets('鸿蒙批量脚本复用 HDC 服务并显示执行结果', (tester) async {
    final hdc = _BatchHdc();
    await withDeviceMenu(
      tester,
      (fixture) async {
        await tester.tap(find.text('执行脚本'));
        await tester.pumpAndSettle();
        final dialog = find.byType(AlertDialog);
        await tester.enterText(
          find.descendant(of: dialog, matching: find.byType(TextField)),
          'echo custom-hdc',
        );
        await tester.tap(find.widgetWithText(FilledButton, '运行'));
        await tester.pumpAndSettle();
        expect(hdc.commands, [(deviceMenuHarmony.id, 'echo custom-hdc')]);
        expect(find.text('custom-hdc-result'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      devices: [deviceMenuHarmony.copyWith(isChecked: true)],
      hdcService: hdc,
    );
  });
}
