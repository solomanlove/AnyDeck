import 'dart:io';

import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/emulator/emulator_service.dart';
import 'package:any_deck/core/harmony/hdc_remote_server.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_wda_host.dart';
import 'package:any_deck/core/process/tool_path_resolver.dart';
import 'package:any_deck/core/scrcpy/scrcpy_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 隔离播放器等原生初始化，保留真实路径保存和窗口广播逻辑。
class _Settings extends AppSettingsController {
  @override
  AppSettings build() => const AppSettings();
}

/// 读取真实加载与广播入口，接收端命名服务不属于本测试。
class _LoadedSettings extends AppSettingsController {
  @override
  Future<void> ensureReceiverNames() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windows = MethodChannel('mixin.one/desktop_multi_window');
  const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final broadcasts = <MethodCall>[];
  late Directory temporary;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    replaceUserToolPaths({});
    customToolPaths.clear();
    broadcasts.clear();
    temporary = await Directory.systemTemp.createTemp('anydeck_tools_');
    messenger.setMockMethodCallHandler(windows, (call) async {
      if (call.method == 'getAllWindows') {
        return [
          {'windowId': 'mirror-test', 'windowArgument': '{"type":"mirror"}'},
        ];
      }
      broadcasts.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(channels, (call) async {
      broadcasts.add(call);
      return null;
    });
  });

  tearDown(() async {
    replaceUserToolPaths({});
    customToolPaths.clear();
    messenger.setMockMethodCallHandler(windows, null);
    messenger.setMockMethodCallHandler(channels, null);
    await temporary.delete(recursive: true);
  });

  Future<File> executable(String name, [String output = 'AnyDeck']) async {
    final suffix = Platform.isWindows ? '.exe' : '';
    final file = File('${temporary.path}/$name$suffix');
    await file.writeAsString('#!/bin/sh\nprintf "%s" "$output"\n');
    if (!Platform.isWindows) await Process.run('chmod', ['700', file.path]);
    return file;
  }

  ProviderContainer container({String windowId = ''}) {
    final value = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWith(_Settings.new),
        windowIdProvider.overrideWithValue(windowId),
      ],
    );
    addTearDown(value.dispose);
    return value;
  }

  test('保存含空格与中文的绝对路径，启动重载且恢复下载默认路径', () async {
    final file = await executable('自定义 adb');
    final downloaded = await executable('downloaded-adb');
    registerCustomToolPath('adb', downloaded.path);
    final scope = container();
    final controller = scope.read(appSettingsProvider.notifier);
    await controller.setToolPath('adb', '  ${file.path}  ', broadcast: false);
    expect(scope.read(appSettingsProvider).toolPaths, {'adb': file.path});
    expect(resolveToolPath('adb'), file.path);
    replaceUserToolPaths({});
    expect(await loadToolPathSettings(), {'adb': file.path});
    expect(resolveToolPath('adb'), file.path);
    await controller.setToolPath('adb', '', broadcast: false);
    expect(resolveToolPath('adb'), downloaded.path);
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        toolPathPreferenceKey('adb'),
      ),
      isFalse,
    );
  });

  test('无效路径与不可执行文件不会覆盖已保存值', () async {
    final file = await executable('adb');
    final scope = container();
    final controller = scope.read(appSettingsProvider.notifier);
    await controller.setToolPath('adb', file.path, broadcast: false);
    final cases = {
      'relative/adb': 'toolPathAbsoluteRequired',
      '${temporary.path}/missing': 'toolPathFileNotFound',
      temporary.path: 'toolPathFileNotFound',
    };
    final plain = await File('${temporary.path}/plain').writeAsString('plain');
    if (!Platform.isWindows) cases[plain.path] = 'toolPathNotExecutable';
    for (final entry in cases.entries) {
      await expectLater(
        controller.setToolPath('adb', entry.key),
        throwsA(
          isA<ToolPathValidationException>().having(
            (e) => e.code,
            'code',
            entry.value,
          ),
        ),
      );
      expect(scope.read(appSettingsProvider).toolPaths['adb'], file.path);
      expect(resolveToolPath('adb'), file.path);
    }
    await expectLater(
      controller.setToolPath('unknown', file.path),
      throwsA(isA<ToolPathValidationException>()),
    );
  });

  test('既有服务在下一次命令读取新路径，同时保留显式注入', () async {
    final file = await executable('all tools', 'custom-result');
    final adb = AdbService();
    final hdc = HdcService();
    final ios = IosCommandService();
    final scrcpy = ScrcpyService();
    final emulator = EmulatorService();
    final wda = IosWdaHost();
    final remote = HdcRemoteServer(
      hdc.executable,
      executableResolver: () => hdc.executable,
    );
    final scope = container();
    for (final tool in configurableToolNames) {
      await scope
          .read(appSettingsProvider.notifier)
          .setToolPath(tool, file.path, broadcast: false);
    }
    expect([
      adb.executable,
      hdc.executable,
      ios.executable,
      scrcpy.executable,
      emulator.executable,
      emulator.avdManagerExecutable,
      wda.forwardExecutable,
      remote.executable,
      resolveToolPath('go-ios'),
    ], everyElement(file.path));
    expect(AdbService(executable: 'fixed-adb').executable, 'fixed-adb');
    expect(HdcService(executable: 'fixed-hdc').executable, 'fixed-hdc');
    expect(IosCommandService(executable: 'fixed-ios').executable, 'fixed-ios');
    expect((await adb.run(['version'])).stdout, 'custom-result');
    expect((await hdc.run(['version'])).stdout, 'custom-result');
    expect((await ios.run(['version'])).stdout, 'custom-result');
  }, skip: Platform.isWindows);

  test('主窗口广播与子窗口上送使用单工具快照', () async {
    final file = await executable('ios');
    final main = container();
    await main.read(appSettingsProvider.notifier).setToolPath('ios', file.path);
    expect(
      broadcasts.any(
        (call) =>
            call.arguments is Map &&
            (call.arguments as Map)['method'] == 'update_tool_path',
      ),
      isTrue,
    );
    broadcasts.clear();
    final child = container(windowId: 'child-test');
    await child
        .read(appSettingsProvider.notifier)
        .setToolPath('adb', file.path);
    final invocation = broadcasts
        .where(
          (call) =>
              call.arguments is Map &&
              (call.arguments as Map)['channel'] == 'any_deck/settings_main',
        )
        .single;
    expect((invocation.arguments as Map)['method'], 'update_tool_path');
    expect((invocation.arguments as Map)['arguments'], {
      'tool': 'adb',
      'path': file.path,
    });
  });

  test('启动加载与接收广播更新同一份解析状态，接收端不重复写入', () async {
    final first = await executable('first-ios');
    final second = await executable('second-ios');
    SharedPreferences.setMockInitialValues({
      toolPathPreferenceKey('ios'): first.path,
    });
    final scope = ProviderContainer(
      overrides: [appSettingsProvider.overrideWith(_LoadedSettings.new)],
    );
    addTearDown(scope.dispose);
    final settings = scope.read(appSettingsProvider.notifier);
    // setToolPath 会等待真实启动加载，不依赖固定时间或轮询。
    await settings.setToolPath('adb', first.path, broadcast: false);
    expect(scope.read(appSettingsProvider).toolPaths['ios'], first.path);
    final response = await messenger.handlePlatformMessage(
      channels.name,
      channels.codec.encodeMethodCall(
        MethodCall('methodCall', {
          'channel': 'any_deck/settings_main',
          'method': 'update_tool_path',
          'arguments': {'tool': 'ios', 'path': second.path},
        }),
      ),
      null,
    );
    if (response != null) channels.codec.decodeEnvelope(response);
    expect(scope.read(appSettingsProvider).toolPaths['ios'], second.path);
    expect(resolveToolPath('go-ios'), second.path);
    expect(
      (await SharedPreferences.getInstance()).getString(
        toolPathPreferenceKey('ios'),
      ),
      first.path,
    );
    expect(broadcasts.where((call) => call.method == 'invokeMethod'), isEmpty);
  });

  test('PATH 定位跳过目录与不可执行文件并返回绝对文件路径', () async {
    final invalid = Directory('${temporary.path}/invalid')..createSync();
    final valid = Directory('${temporary.path}/valid')..createSync();
    final tool = Platform.isWindows ? 'probe.exe' : 'probe';
    await Directory('${invalid.path}/$tool').create();
    final file = await File('${valid.path}/$tool').writeAsString('probe');
    if (!Platform.isWindows) await Process.run('chmod', ['700', file.path]);
    final separator = Platform.isWindows ? ';' : ':';
    expect(
      resolveToolFromPath(
        'probe',
        searchPath: '${invalid.path}$separator${valid.path}',
      ),
      file.path,
    );
    expect(resolveToolFromPath('missing', searchPath: valid.path), isNull);
  });
}
