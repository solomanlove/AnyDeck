import 'dart:io';

import 'package:any_deck/app/widget/app_toast.dart';
import 'package:any_deck/core/process/host_platform_service.dart';
import 'package:any_deck/core/process/tool_path_resolver.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/devices/controller/platform_tools_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shortcut_test_fixture.dart';

/// 记录目录启动参数，验证真实 Controller 而不打开系统应用。
class _Host extends HostPlatformService {
  final opened = <(String, bool)>[];
  bool succeeds = true;
  bool throwsError = false;

  @override
  Future<bool> openDirectory(String dirPath) async => _record(dirPath, false);

  @override
  Future<bool> openTerminal(String dirPath) async => _record(dirPath, true);

  bool _record(String path, bool terminal) {
    if (throwsError) throw const FileSystemException('test error');
    opened.add((path, terminal));
    return succeeds;
  }
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
      }
    }
    expect(host.opened, hasLength(6));
    expect(tester.takeException(), isNull);
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
