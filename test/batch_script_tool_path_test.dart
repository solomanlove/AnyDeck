import 'dart:ffi';
import 'dart:io';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/dal/rust_dal_bridge.dart';
import 'package:any_deck/core/process/tool_path_resolver.dart';
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

/// 其他设备查询仍隔离，只有被审查的脚本链路交给真实 ADB 命令封装。
class _BatchAdb extends DeviceMenuAdb {
  _BatchAdb(this.tester);

  final WidgetTester tester;
  Future<AdbResult?>? pending;

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    pending = tester.runAsync(
      () => AdbService().shell(deviceId, command, timeout: timeout),
    );
    return (await pending)!;
  }
}

void main() {
  testWidgets('仅选择 iOS 时批量脚本禁用，不将设备交给 ADB 或 HDC', (tester) async {
    await withDeviceMenu(tester, (fixture) async {
      await tester.tap(find.byKey(const Key('deviceBatchManage')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deviceBatchActions')));
      await tester.pumpAndSettle();
      final script = find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<String> && widget.value == 'script',
      );
      expect(script, findsOneWidget);
      expect(tester.widget<PopupMenuItem<String>>(script).enabled, isFalse);
    }, devices: [deviceMenuIos.copyWith(isChecked: true)]);
  });

  testWidgets('Android 批量脚本通过新 ADB 文件执行并保留完整参数', (tester) async {
    final temporary = Directory.systemTemp.createTempSync('anydeck batch adb ');
    final calls = File('${temporary.path}/calls');
    final executable = File('${temporary.path}/custom adb');
    executable.writeAsStringSync(
      '#!/bin/sh\nprintf "%s\\n" "\$@" > "${calls.path}"\n'
      'printf "custom-adb-result"\n',
    );
    await tester.runAsync(() => Process.run('chmod', ['700', executable.path]));
    replaceUserToolPaths({'adb': executable.path});
    final adb = _BatchAdb(tester);
    addTearDown(() {
      replaceUserToolPaths({});
      temporary.deleteSync(recursive: true);
    });
    await withDeviceMenu(
      tester,
      (fixture) async {
        expect(resolveToolPath('adb'), executable.path);
        await tester.tap(find.byKey(const Key('deviceBatchManage')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('deviceBatchActions')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('执行脚本'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          'echo custom-adb',
        );
        await tester.tap(find.widgetWithText(FilledButton, '运行'));
        await tester.pump();
        expect(adb.pending, isNotNull);
        await adb.pending;
        await tester.pumpAndSettle();
        expect(find.text('custom-adb-result'), findsOneWidget);
        expect(calls.readAsLinesSync(), [
          '-s',
          deviceMenuAndroid.id,
          'shell',
          'echo custom-adb',
        ]);
        // 可注入必然成功的 DAL，确认不是“先走旧通道失败，再回退新 CLI”。
        if (Platform.environment['ANYDECK_TOOL_PATH_DAL_STUB'] == '1') {
          expect(RustDalBridge.instance.isAvailable, isTrue);
          final library = DynamicLibrary.open(
            Platform.environment['ANYDECK_DEVICE_BRIDGE']!,
          );
          final nativeCalls = library
              .lookupFunction<Int32 Function(), int Function()>(
                'test_native_calls',
              );
          expect(nativeCalls(), 0);
        }
        expect(tester.takeException(), isNull);
      },
      devices: [deviceMenuAndroid.copyWith(isChecked: true)],
      adbService: adb,
    );
  }, skip: Platform.isWindows);

  testWidgets('鸿蒙批量脚本复用 HDC 服务并显示执行结果', (tester) async {
    final hdc = _BatchHdc();
    await withDeviceMenu(
      tester,
      (fixture) async {
        await tester.tap(find.byKey(const Key('deviceBatchManage')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('deviceBatchActions')));
        await tester.pumpAndSettle();
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
