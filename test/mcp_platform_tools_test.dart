import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/mcp/registry/mcp_registry_factory.dart';
import 'package:any_deck/core/mcp/tools/mcp_ios_diagnostic_tools.dart';

class _Adb extends AdbService {
  @override
  Future<List<DiscoveredDevice>> listDevices() async => [];
  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async => throw StateError('HarmonyOS 不得走 ADB: $args');
}

class _Hdc extends HdcService {
  final commands = <String>[];
  @override
  Future<List<DiscoveredDevice>> listDevices() async => const [
    DiscoveredDevice(id: 'h', status: 'device', isHarmony: true),
  ];
  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(command);
    return AdbResult(
      exitCode: 0,
      stdout: command == 'bm dump -a -l'
          ? '["com.example.app"]'
          : 'test output',
      stderr: '',
    );
  }
}

class _IosDevices extends IosDeviceService {
  @override
  Future<List<DiscoveredDevice>> listDevices() async => [];
}

class _IosCommands extends IosCommandService {
  Process? process;
  @override
  Future<Process> startSyslog(String udid) async {
    process = await Process.start('/usr/bin/python3', [
      '-u',
      '-c',
      'import time\nfor i in range(100): print("sample", flush=True)\ntime.sleep(30)',
    ]);
    return process!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('HarmonyOS 发现、概览、点击滑动输入、应用和日志均通过 HDC', () async {
    final hdc = _Hdc();
    final registry = McpRegistryFactory(
      adb: _Adb(),
      hdc: hdc,
      iosDevices: _IosDevices(),
      iosCommands: _IosCommands(),
    ).create();
    Future<Map<String, dynamic>> call(
      String name, [
      Map<String, dynamic> args = const {},
    ]) => registry.executeTool(
      name: name,
      arguments: {'deviceId': 'h', ...args},
      platform: 'harmony',
    );
    final discovered = await registry.executeTool(
      name: 'list_devices',
      arguments: {},
      platform: 'harmony',
    );
    expect(discovered['count'], 1);
    await call('get_device_detail');
    await call('device_input_tap', {'x': 10, 'y': 20});
    await call('device_input_swipe', {'x1': 1, 'y1': 2, 'x2': 3, 'y2': 4});
    await call('device_input_text', {'text': "你好' test"});
    await call('list_installed_apps');
    await call('query_hilog');
    expect(hdc.commands, contains('uitest uiInput click 10 20'));
    expect(hdc.commands, contains('uitest uiInput swipe 1 2 3 4'));
    expect(hdc.commands.any((c) => c.startsWith('uitest uiInput text')), true);
    expect(hdc.commands, contains('bm dump -a -l'));
    expect(hdc.commands, contains('hilog -x -t 500'));
    await expectLater(
      registry.executeTool(
        name: 'uninstall_app',
        arguments: {'deviceId': 'h', 'packageName': 'com.app; reboot'},
        enableDangerousGuard: false,
        platform: 'harmony',
      ),
      throwsArgumentError,
    );
    expect(hdc.commands.any((c) => c.contains('reboot')), false);
  });
  test('iOS 日志达到行数后终止子进程，结果和内存均有界', () async {
    final commands = _IosCommands();
    final result = await McpIosDiagnosticTools(commands)
        .getTools()
        .singleWhere((t) => t.name == 'ios_query_syslog')
        .handler({'deviceId': 'i', 'limitLines': 2});
    expect(result['logs'], hasLength(2));
    expect(result['truncated'], true);
    expect(
      await commands.process!.exitCode.timeout(const Duration(seconds: 1)),
      isNotNull,
    );
  });
}
