import 'dart:async';
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
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

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
    final snapshot = await messenger.handlePlatformMessage(
      channels.name,
      channels.codec.encodeMethodCall(
        MethodCall('methodCall', {
          'channel': 'any_deck/settings_main',
          'method': 'resolve_tool_paths',
        }),
      ),
      null,
    );
    expect(channels.codec.decodeEnvelope(snapshot!), {
      'adb': first.path,
      'ios': second.path,
    });
  });

  test('PATH 定位跳过目录和当前用户不可执行文件并返回绝对文件路径', () async {
    final invalid = Directory('${temporary.path}/invalid')..createSync();
    final denied = Directory('${temporary.path}/denied')..createSync();
    final valid = Directory('${temporary.path}/valid')..createSync();
    final tool = Platform.isWindows ? 'probe.exe' : 'probe';
    await Directory('${invalid.path}/$tool').create();
    final file = await File('${valid.path}/$tool').writeAsString('probe');
    if (!Platform.isWindows) await Process.run('chmod', ['700', file.path]);
    if (!Platform.isWindows) {
      final inaccessible = await File(
        '${denied.path}/$tool',
      ).writeAsString('probe');
      final user = await Process.run('id', ['-u']);
      final mode = user.stdout.toString().trim() == '0' ? '000' : '001';
      await Process.run('chmod', [mode, inaccessible.path]);
    }
    final separator = Platform.isWindows ? ';' : ':';
    expect(
      resolveToolFromPath(
        'probe',
        searchPath: [
          invalid.path,
          if (!Platform.isWindows) denied.path,
          valid.path,
        ].join(separator),
      ),
      file.path,
    );
    expect(resolveToolFromPath('missing', searchPath: valid.path), isNull);
  });

  test('启动加载刷新其他 Engine 已经更新的 Preference 缓存', () async {
    final first = await executable('old-ios');
    final second = await executable('new-ios');
    final key = toolPathPreferenceKey('ios');
    SharedPreferences.setMockInitialValues({key: first.path});
    final preferences = await SharedPreferences.getInstance();
    expect(await loadToolPathSettings(preferences: preferences), {
      'ios': first.path,
    });
    // 模拟主窗口在子 Engine 首次读取后、设置通道就绪前保存了新路径。
    await SharedPreferencesStorePlatform.instance.setValue(
      'String',
      'flutter.$key',
      second.path,
    );
    expect(preferences.getString(key), first.path);
    expect(await loadToolPathSettings(preferences: preferences), {
      'ios': second.path,
    });
    expect(resolveToolPath('ios'), second.path);
  });

  test('广播遇到未就绪窗口仍同步后续活动窗口', () async {
    messenger.setMockMethodCallHandler(windows, (call) async {
      if (call.method != 'getAllWindows') return null;
      return [
        {'windowId': 'unready', 'windowArgument': '{"type":"mirror"}'},
        {'windowId': 'live', 'windowArgument': '{"type":"mirror"}'},
      ];
    });
    messenger.setMockMethodCallHandler(channels, (call) async {
      broadcasts.add(call);
      if ((call.arguments as Map)['channel'] ==
          'mixin.one/window_controller/unready') {
        throw PlatformException(code: 'CHANNEL_NOT_FOUND');
      }
      return null;
    });
    final scope = container();
    await scope.read(appSettingsProvider.notifier).setToolPath('ios', '');
    expect(
      broadcasts.any(
        (call) =>
            (call.arguments as Map)['channel'] ==
            'mixin.one/window_controller/live',
      ),
      isTrue,
    );
  });

  test('子窗口上送失败仍向其他活动窗口同步', () async {
    messenger.setMockMethodCallHandler(channels, (call) async {
      broadcasts.add(call);
      if ((call.arguments as Map)['channel'] == 'any_deck/settings_main') {
        throw PlatformException(code: 'CHANNEL_UNREGISTERED');
      }
      return null;
    });
    final scope = container(windowId: 'child-test');
    await scope.read(appSettingsProvider.notifier).setToolPath('ios', '');
    expect(
      broadcasts.any(
        (call) =>
            (call.arguments as Map)['channel'] ==
            'mixin.one/window_controller/mirror-test',
      ),
      isTrue,
    );
  });

  for (final mainWindow in [true, false]) {
    testWidgets('无响应${mainWindow ? '主' : '子'}窗口超过同步时限后继续广播并释放调用', (
      tester,
    ) async {
      final unresponsive = Completer<Object?>();
      addTearDown(() => unresponsive.complete(null));
      messenger.setMockMethodCallHandler(windows, (call) async {
        if (call.method != 'getAllWindows') return null;
        return [
          if (!mainWindow)
            {'windowId': 'unresponsive', 'windowArgument': '{"type":"mirror"}'},
          {'windowId': 'live', 'windowArgument': '{"type":"mirror"}'},
        ];
      });
      messenger.setMockMethodCallHandler(channels, (call) async {
        broadcasts.add(call);
        if ((call.arguments as Map)['channel'] ==
            (mainWindow
                ? 'any_deck/settings_main'
                : 'mixin.one/window_controller/unresponsive')) {
          return unresponsive.future;
        }
        return null;
      });
      final scope = container(windowId: mainWindow ? 'child-test' : '');
      final sending = scope
          .read(appSettingsProvider.notifier)
          .setToolPath('ios', '');
      await tester.pump();
      await tester.pump(const Duration(seconds: 16));
      await sending;
      expect(
        broadcasts.any(
          (call) =>
              (call.arguments as Map)['channel'] ==
              'mixin.one/window_controller/live',
        ),
        isTrue,
      );
    });
  }

  test('其他用户有执行位但当前用户无权限时不覆盖原路径', () async {
    final user = await Process.run('id', ['-u']);
    if (user.stdout.toString().trim() == '0') {
      markTestSkipped('root 会绕过普通用户的文件权限检查');
      return;
    }
    final original = await executable('working-adb');
    final denied = await executable('other-user-adb');
    await Process.run('chmod', ['001', denied.path]);
    final scope = container();
    final controller = scope.read(appSettingsProvider.notifier);
    await controller.setToolPath('adb', original.path, broadcast: false);
    await expectLater(
      controller.setToolPath('adb', denied.path, broadcast: false),
      throwsA(
        isA<ToolPathValidationException>().having(
          (error) => error.code,
          'code',
          'toolPathNotExecutable',
        ),
      ),
    );
    expect(scope.read(appSettingsProvider).toolPaths['adb'], original.path);
    expect(resolveToolPath('adb'), original.path);
  }, skip: Platform.isWindows);
}
