import 'dart:async';
import 'dart:io';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/process/tool_path_resolver.dart';
import 'package:any_deck/features/overview/settings/settings_item.dart';
import 'package:any_deck/features/overview/settings/settings_workspace.dart';
import 'package:any_deck/features/overview/settings/tool_path_settings_catalog.dart';
import 'package:any_deck/features/overview/widget/tool_path_setting_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 仅隔离原生启动初始化，路径校验、保存、状态更新与广播继续使用真实实现。
class _PathSettings extends AppSettingsController {
  @override
  AppSettings build() => const AppSettings();
}

/// 使用真实主题与双语文案验证编辑器，不启动 CLI 或系统文件选择器。
Widget _harness({
  String language = 'zh',
  Brightness brightness = Brightness.light,
  required Widget child,
}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildAppTheme(brightness),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Finder _key(String action) => find.byKey(ValueKey('tool-$action-adb'));

/// 等待真实文件检查完成，避免在恢复按钮前点击异步检测中的操作。
Future<void> _waitForOpenActions(WidgetTester tester, bool enabled) async {
  await tester.runAsync(() async {
    for (var attempt = 0; attempt < 200; attempt++) {
      final directory = tester.widget<TextButton>(_key('open-directory'));
      final terminal = tester.widget<TextButton>(_key('open-terminal'));
      if ((directory.onPressed != null) == enabled &&
          (terminal.onPressed != null) == enabled) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
      await tester.pump();
    }
    fail('目录操作未在预期时间内变为 ${enabled ? '可用' : '禁用'}');
  });
}

void main() {
  testWidgets('真实设置目录通过搜索配置 iOS，保存、非法输入与恢复默认保持一致', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    replaceUserToolPaths({});
    final scope = ProviderContainer(
      overrides: [appSettingsProvider.overrideWith(_PathSettings.new)],
    );
    const windows = MethodChannel('mixin.one/desktop_multi_window');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(windows, (call) async {
      if (call.method == 'getAllWindows') return <Object>[];
      return null;
    });
    late Directory temporary;
    late String executable;
    await tester.runAsync(() async {
      temporary = await Directory.systemTemp.createTemp('anydeck_ui_tools_');
      executable =
          '${temporary.path}/custom ios${Platform.isWindows ? '.exe' : ''}';
      await File(executable).writeAsString('AnyDeck test executable');
      if (!Platform.isWindows) {
        await Process.run('chmod', ['700', executable]);
      }
    });
    addTearDown(() async {
      scope.dispose();
      replaceUserToolPaths({});
      messenger.setMockMethodCallHandler(windows, null);
      await temporary.delete(recursive: true);
    });
    final defaultPath = resolveToolPath('ios');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: _harness(
          child: SizedBox(
            height: 850,
            child: Builder(
              builder: (context) => SettingsWorkspace(
                items: [
                  const SettingsItem(
                    id: 'general',
                    category: SettingsCategory.general,
                    section: 'General',
                    title: 'General',
                    child: SizedBox(),
                  ),
                  ...buildToolPathSettingsItems(context),
                ],
                cardBuilder: (title, children) =>
                    Card(child: Column(children: [Text(title), ...children])),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('settings-search')),
      'iOS 设备管理',
    );
    await tester.pumpAndSettle();
    final result = find.byKey(const ValueKey('settings-result-toolPath-ios'));
    expect(result, findsOneWidget);
    await tester.tap(result);
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('tool-path-ios'));
    final save = find.byKey(const ValueKey('tool-save-ios'));
    final reset = find.byKey(const ValueKey('tool-reset-ios'));
    final current = find.byKey(const ValueKey('tool-current-ios'));
    // 文件 stat 与原生广播使用真实异步队列，等待编辑器恢复可操作后再断言。
    Future<void> apply(Finder action) async {
      await tester.tap(action);
      await tester.pump();
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 200; attempt++) {
          if (tester.widget<TextField>(input).enabled == true) return;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          await tester.pump();
        }
        fail('路径操作未在预期时间内完成');
      });
      await tester.pumpAndSettle();
    }

    expect(input.hitTestable(), findsOneWidget);
    await tester.enterText(input, executable);
    await apply(save);
    expect(scope.read(appSettingsProvider).toolPaths['ios'], executable);
    expect(resolveToolPath('go-ios'), executable);
    expect(tester.widget<SelectableText>(current).data, contains(executable));
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(toolPathPreferenceKey('ios')), executable);

    await tester.enterText(input, '${temporary.path}/missing');
    await apply(save);
    expect(find.text('文件不存在，请选择工具的可执行文件。'), findsOneWidget);
    expect(scope.read(appSettingsProvider).toolPaths['ios'], executable);
    expect(preferences.getString(toolPathPreferenceKey('ios')), executable);
    expect(tester.widget<SelectableText>(current).data, contains(executable));

    await apply(reset);
    expect(
      scope.read(appSettingsProvider).toolPaths.containsKey('ios'),
      isFalse,
    );
    expect(preferences.containsKey(toolPathPreferenceKey('ios')), isFalse);
    expect(resolveToolPath('ios'), defaultPath);
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('核心依赖编辑器 $language $brightness 窄窗口可保存和恢复默认', (tester) async {
        tester.view.physicalSize = const Size(360, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        late Directory temporary;
        late String executable;
        await tester.runAsync(() async {
          temporary = await Directory.systemTemp.createTemp('anydeck tool UI ');
          executable =
              '${temporary.path}/中文 adb${Platform.isWindows ? '.exe' : ''}';
          await File(executable).writeAsString('AnyDeck test executable');
          if (!Platform.isWindows) {
            await Process.run('chmod', ['700', executable]);
          }
        });
        addTearDown(() => temporary.delete(recursive: true));
        var current = '';
        final opened = <bool>[];
        await tester.pumpWidget(
          _harness(
            language: language,
            brightness: brightness,
            child: StatefulBuilder(
              builder: (context, update) => ToolPathSettingField(
                toolName: 'adb',
                value: current,
                resolvedPath: current.isEmpty
                    ? '${temporary.path}/missing-adb'
                    : current,
                onChanged: (path) async => update(() => current = path),
                onOpen: (terminal) async => opened.add(terminal),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.widget<TextButton>(_key('open-directory')).onPressed,
          isNull,
        );
        expect(
          tester.widget<TextButton>(_key('open-terminal')).onPressed,
          isNull,
        );
        await tester.enterText(_key('path'), '  $executable  ');
        await tester.tap(_key('save'));
        await tester.pump();
        expect(current, executable);
        final display = tester.widget<SelectableText>(_key('current'));
        expect(display.data, contains(executable));
        await _waitForOpenActions(tester, true);
        await tester.tap(_key('open-directory'));
        await tester.pump();
        await _waitForOpenActions(tester, true);
        await tester.tap(_key('open-terminal'));
        await tester.pump();
        expect(opened, [false, true]);
        await tester.tap(_key('reset'));
        await tester.pump();
        await _waitForOpenActions(tester, false);
        expect(current, isEmpty);
        expect(
          tester.widget<TextField>(_key('path')).controller!.text,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('保存失败显示校验文案并保留已保存路径和输入草稿', (tester) async {
    await tester.pumpWidget(
      _harness(
        child: ToolPathSettingField(
          toolName: 'adb',
          value: '/old/adb',
          resolvedPath: '/old/adb',
          onChanged: (_) async =>
              throw const ToolPathValidationException('toolPathFileNotFound'),
          onOpen: (_) async {},
        ),
      ),
    );
    await tester.enterText(_key('path'), '/missing/adb');
    await tester.tap(_key('save'));
    await tester.pump();
    expect(find.text('文件不存在，请选择工具的可执行文件。'), findsOneWidget);
    expect(
      tester.widget<TextField>(_key('path')).controller!.text,
      '/missing/adb',
    );
    expect(
      tester.widget<SelectableText>(_key('current')).data,
      contains('/old/adb'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('选择文件保留为草稿，取消不修改；保存期间禁止重复操作', (tester) async {
    var selected = '/chosen/adb';
    final saved = <String>[];
    final completion = Completer<void>();
    await tester.pumpWidget(
      _harness(
        child: ToolPathSettingField(
          toolName: 'adb',
          value: '',
          resolvedPath: '/default/adb',
          pickFile: () async => selected.isEmpty ? null : selected,
          onChanged: (path) async {
            saved.add(path);
            await completion.future;
          },
          onOpen: (_) async {},
        ),
      ),
    );
    await tester.tap(_key('choose'));
    await tester.pump();
    expect(saved, isEmpty);
    expect(
      tester.widget<TextField>(_key('path')).controller!.text,
      '/chosen/adb',
    );
    selected = '';
    await tester.tap(_key('choose'));
    await tester.pump();
    expect(
      tester.widget<TextField>(_key('path')).controller!.text,
      '/chosen/adb',
    );
    await tester.tap(_key('save'));
    await tester.pump();
    expect(saved, ['/chosen/adb']);
    expect(tester.widget<TextField>(_key('path')).enabled, isFalse);
    expect(tester.widget<FilledButton>(_key('save')).onPressed, isNull);
    expect(tester.widget<TextButton>(_key('open-directory')).onPressed, isNull);
    completion.complete();
    await tester.pump();
    expect(tester.widget<TextField>(_key('path')).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('全部核心工具可通过目录与终端关键词检索', (tester) async {
    for (final language in ['zh', 'en']) {
      late List<SettingsItem> items;
      await tester.pumpWidget(
        _harness(
          language: language,
          child: Builder(
            builder: (context) {
              items = buildToolPathSettingsItems(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(items.length, configurableToolNames.length);
      for (final tool in configurableToolNames) {
        final item = items.singleWhere((item) => item.id == 'toolPath-$tool');
        expect(item.category, SettingsCategory.dependencies);
        expect(item.matches('$tool terminal', ''), isTrue);
        expect(item.title, isNot(startsWith('toolPathTitle-')));
        expect(item.searchLabels, hasLength(4));
      }
    }
  });
}
