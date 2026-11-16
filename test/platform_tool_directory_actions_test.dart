import 'dart:io';

import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/widget/app_toast.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/core/process/host_platform_service.dart';
import 'package:any_deck/core/process/tool_path_resolver.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/devices/controller/platform_tools_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/shortcut_test_fixture.dart';

/// 记录目录启动参数，验证真实 Controller 而不打开系统应用。
class _Host extends HostPlatformService {
  final opened = <(String, bool)>[];
  bool succeeds = true;
  bool throwsError = false;
  final toolTerminals = <(String, String)>[];

  @override
  Future<bool> openDirectory(String dirPath) async => _record(dirPath, false);

  @override
  Future<bool> openTerminal(String dirPath) async => _record(dirPath, true);

  @override
  Future<bool> openToolTerminal(String executable, String toolName) async {
    toolTerminals.add((executable, toolName));
    return _record(File(executable).parent.path, true);
  }

  bool _record(String path, bool terminal) {
    if (throwsError) throw const FileSystemException('test error');
    opened.add((path, terminal));
    return succeeds;
  }
}

/// 保留实际保存和广播方法，仅隔离与本测试无关的原生设置初始化。
class _Settings extends AppSettingsController {
  _Settings(this.paths);
  final Map<String, String> paths;

  @override
  AppSettings build() => AppSettings(toolPaths: paths);
}

void main() {
  late Directory tools;
  late _Host host;
  late ProviderContainer container;

  setUp(() async {
    tools = await Directory.systemTemp.createTemp('anydeck tool actions ');
    host = _Host();
    container = ProviderContainer(
      overrides: [hostPlatformServiceProvider.overrideWithValue(host)],
    );
    final paths = <String, String>{};
    for (final tool in ['adb', 'hdc', 'ios']) {
      final executable = await File('${tools.path}/$tool').create();
      paths[tool] = executable.path;
    }
    replaceUserToolPaths(paths);
  });

  tearDown(() async {
    container.dispose();
    replaceUserToolPaths({});
    await tools.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester, String language) => tester.pumpWidget(
    shortcutTestApp(
      container: container,
      language: language,
      child: Consumer(
        builder: (context, ref, _) => Column(
          children: [
            for (final tool in ['adb', 'hdc', 'ios'])
              for (final terminal in [false, true])
                TextButton(
                  onPressed: () => PlatformToolsController.openToolDirectory(
                    context,
                    ref,
                    tool,
                    terminal: terminal,
                  ),
                  child: Text('$tool:$terminal'),
                ),
          ],
        ),
      ),
    ),
  );

  testWidgets('三平台目录与终端使用已配置路径，支持含空格目录', (tester) async {
    await mount(tester, 'zh');
    for (final tool in ['adb', 'hdc', 'ios']) {
      for (final terminal in [false, true]) {
        await tester.tap(find.text('$tool:$terminal'));
        await tester.pumpAndSettle();
        expect(host.opened.last, (tools.path, terminal));
        if (terminal) {
          expect(host.toolTerminals.last, ('${tools.path}/$tool', tool));
        }
      }
    }
    expect(host.opened, hasLength(6));
    expect(tester.takeException(), isNull);
    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('既有服务保存替换路径后，目录与工具终端均使用新文件', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const windows = MethodChannel('mixin.one/desktop_multi_window');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(windows, (call) async => <Object>[]);
    addTearDown(() => messenger.setMockMethodCallHandler(windows, null));
    container.dispose();
    container = ProviderContainer(
      overrides: [
        hostPlatformServiceProvider.overrideWithValue(host),
        appSettingsProvider.overrideWith(
          () => _Settings({
            for (final tool in ['adb', 'hdc', 'ios'])
              tool: '${tools.path}/$tool',
          }),
        ),
      ],
    );
    // 在保存前创建服务，专门检查既有实例是否仍缓存旧路径。
    final adb = container.read(adbServiceProvider);
    final hdc = container.read(hdcServiceProvider);
    final ios = container.read(iosCommandServiceProvider);
    await mount(tester, 'zh');
    final newDirectory = Directory('${tools.path}/替换工具')..createSync();
    for (final tool in ['adb', 'hdc', 'ios']) {
      final file = File(
        '${newDirectory.path}/custom-$tool${Platform.isWindows ? '.exe' : ''}',
      )..writeAsStringSync('AnyDeck');
      await tester.runAsync(() async {
        if (!Platform.isWindows) await Process.run('chmod', ['700', file.path]);
        await container
            .read(appSettingsProvider.notifier)
            .setToolPath(tool, file.path);
      });
      await tester.tap(find.text('$tool:false'));
      await tester.pumpAndSettle();
      expect(host.opened.last, (newDirectory.path, false));
      await tester.tap(find.text('$tool:true'));
      await tester.pumpAndSettle();
      expect(host.opened.last, (newDirectory.path, true));
      expect(host.toolTerminals.last, (file.path, tool));
      expect(switch (tool) {
        'adb' => adb.executable,
        'hdc' => hdc.executable,
        _ => ios.executable,
      }, file.path);
    }
    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('iOS 目录与终端使用命令服务实际选择的 go-ios 文件', (tester) async {
    final fallback = File('${tools.path}/go-ios')..createSync();
    container.dispose();
    container = ProviderContainer(
      overrides: [
        hostPlatformServiceProvider.overrideWithValue(host),
        iosCommandServiceProvider.overrideWithValue(
          IosCommandService(executable: fallback.path),
        ),
      ],
    );
    await mount(tester, 'zh');
    await tester.tap(find.text('ios:false'));
    await tester.pumpAndSettle();
    expect(host.opened.last, (tools.path, false));
    await tester.tap(find.text('ios:true'));
    await tester.pumpAndSettle();
    expect(host.toolTerminals.last, (fallback.path, 'ios'));
    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('路径被删除后提示缺失，不打开其他工具目录', (tester) async {
    await mount(tester, 'en');
    File('${tools.path}/ios').deleteSync();
    await tester.tap(find.text('ios:false'));
    await tester.pumpAndSettle();
    expect(host.opened, isEmpty);
    expect(find.textContaining('directory not detected'), findsOneWidget);
    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('系统打开失败和异常使用当前语言反馈', (tester) async {
    await mount(tester, 'en');
    host.succeeds = false;
    await tester.tap(find.text('ios:false'));
    await tester.pumpAndSettle();
    expect(find.text('Failed to open iOS (go-ios) directory'), findsOneWidget);
    await tester.tap(find.text('ios:true'));
    await tester.pumpAndSettle();
    expect(find.text('Failed to open iOS (go-ios) terminal'), findsOneWidget);
    host.throwsError = true;
    await tester.tap(find.text('ios:true'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed to open tool:'), findsOneWidget);
    expect(tester.takeException(), isNull);
    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
