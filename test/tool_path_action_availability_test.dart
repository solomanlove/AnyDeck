import 'dart:io';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/process/tool_path_settings.dart';
import 'package:any_deck/features/overview/widget/tool_path_setting_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 使用真实主题与临时可执行文件，验证目录入口跟随已应用工具的检测状态。
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

Finder _control(String tool, String action) =>
    find.byKey(ValueKey('tool-$action-$tool'));

Finder _warning(String tool) => find.byKey(ValueKey('tool-unavailable-$tool'));

void _expectOpenActions(WidgetTester tester, String tool, bool enabled) {
  for (final action in ['open-directory', 'open-terminal']) {
    expect(
      tester.widget<TextButton>(_control(tool, action)).onPressed,
      enabled ? isNotNull : isNull,
      reason: '$tool $action 应${enabled ? '可用' : '禁用'}',
    );
  }
}

/// 文件检查使用真实 I/O 队列；同时等待徽标和按钮到达一致状态。
Future<void> _waitForAvailability(
  WidgetTester tester,
  String tool, {
  required bool available,
}) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump();
    final actionsEnabled = ['open-directory', 'open-terminal'].every(
      (action) =>
          tester.widget<TextButton>(_control(tool, action)).onPressed != null,
    );
    final warningVisible = _warning(tool).evaluate().isNotEmpty;
    if (actionsEnabled == available && warningVisible == !available) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('$tool 的检测结果与目录按钮没有到达预期状态：available=$available');
}

Future<File> _executable(Directory directory, String tool) async {
  final file = await File(
    '${directory.path}/可执行 $tool${Platform.isWindows ? '.exe' : ''}',
  ).writeAsString('AnyDeck test executable');
  if (!Platform.isWindows) {
    expect((await Process.run('chmod', ['700', file.path])).exitCode, 0);
  }
  return file;
}

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('anydeck tool actions ');
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  for (final tool in configurableToolNames) {
    testWidgets('$tool 缺失或检测中禁用目录入口，可用后点击使用正确操作', (tester) async {
      late File executable;
      await tester.runAsync(() async {
        executable = await _executable(temporary, tool);
      });
      var resolvedPath = tool;
      late StateSetter update;
      final opened = <bool>[];
      await tester.pumpWidget(
        _harness(
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return ToolPathSettingField(
                toolName: tool,
                value: '',
                resolvedPath: resolvedPath,
                onChanged: (_) async {},
                onOpen: (terminal) async => opened.add(terminal),
              );
            },
          ),
        ),
      );
      _expectOpenActions(tester, tool, false);
      await _waitForAvailability(tester, tool, available: false);
      await tester.tap(_control(tool, 'open-directory'));
      await tester.tap(_control(tool, 'open-terminal'));
      expect(opened, isEmpty);

      update(() => resolvedPath = executable.path);
      await tester.pump();
      _expectOpenActions(tester, tool, false);
      await _waitForAvailability(tester, tool, available: true);
      _expectOpenActions(tester, tool, true);
      await tester.tap(_control(tool, 'open-directory'));
      await _waitForAvailability(tester, tool, available: true);
      await tester.tap(_control(tool, 'open-terminal'));
      await _waitForAvailability(tester, tool, available: true);
      expect(opened, [false, true]);

      // 替换成缺失路径后，不能在新结果返回前继续使用旧路径的可用状态。
      update(() => resolvedPath = '${temporary.path}/missing-$tool');
      await tester.pump();
      _expectOpenActions(tester, tool, false);
      await _waitForAvailability(tester, tool, available: false);
      await tester.tap(_control(tool, 'open-directory'));
      await tester.tap(_control(tool, 'open-terminal'));
      expect(opened, [false, true]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('选择与输入有效草稿保持置灰，保存恢复入口，恢复缺失默认路径再禁用', (tester) async {
    late File executable;
    await tester.runAsync(() async {
      executable = await _executable(temporary, 'hdc');
    });
    var applied = '';
    final saved = <String>[];
    await tester.pumpWidget(
      _harness(
        child: StatefulBuilder(
          builder: (context, update) => ToolPathSettingField(
            toolName: 'hdc',
            value: applied,
            resolvedPath: applied.isEmpty ? 'hdc' : applied,
            pickFile: () async => executable.path,
            onChanged: (path) async {
              final validated = await validateToolPath('hdc', path);
              saved.add(validated);
              update(() => applied = validated);
            },
            onOpen: (_) async {},
          ),
        ),
      ),
    );
    await _waitForAvailability(tester, 'hdc', available: false);
    expect(
      tester.widget<OutlinedButton>(_control('hdc', 'choose')).onPressed,
      isNotNull,
    );
    await tester.tap(_control('hdc', 'choose'));
    await _waitForAvailability(tester, 'hdc', available: false);
    expect(
      tester.widget<TextField>(_control('hdc', 'path')).controller!.text,
      executable.path,
    );
    await tester.enterText(_control('hdc', 'path'), '  ${executable.path}  ');
    await tester.pump();
    _expectOpenActions(tester, 'hdc', false);
    expect(saved, isEmpty);

    await tester.tap(_control('hdc', 'save'));
    await _waitForAvailability(tester, 'hdc', available: true);
    expect(saved, [executable.path]);
    _expectOpenActions(tester, 'hdc', true);
    await tester.tap(_control('hdc', 'reset'));
    await _waitForAvailability(tester, 'hdc', available: false);
    expect(saved, [executable.path, '']);
    _expectOpenActions(tester, 'hdc', false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文件删除后返回应用禁用目录入口，原路径恢复后重新启用', (tester) async {
    late File executable;
    await tester.runAsync(() async {
      executable = await _executable(temporary, 'ios');
    });
    await tester.pumpWidget(
      _harness(
        child: ToolPathSettingField(
          toolName: 'ios',
          value: executable.path,
          resolvedPath: executable.path,
          onChanged: (_) async {},
          onOpen: (_) async {},
        ),
      ),
    );
    await _waitForAvailability(tester, 'ios', available: true);
    executable.deleteSync();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    _expectOpenActions(tester, 'ios', false);
    await _waitForAvailability(tester, 'ios', available: false);

    await tester.runAsync(() => _executable(temporary, 'ios'));
    _expectOpenActions(tester, 'ios', false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _waitForAvailability(tester, 'ios', available: true);
    _expectOpenActions(tester, 'ios', true);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('工具缺失时 $language $brightness 窄窗口入口置灰，配置操作保留', (tester) async {
        tester.view.physicalSize = const Size(360, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var opened = false;
        await tester.pumpWidget(
          _harness(
            language: language,
            brightness: brightness,
            child: ToolPathSettingField(
              toolName: 'hdc',
              value: '${temporary.path}/missing-hdc',
              resolvedPath: '${temporary.path}/missing-hdc',
              onChanged: (_) async {},
              onOpen: (_) async => opened = true,
            ),
          ),
        );
        await _waitForAvailability(tester, 'hdc', available: false);
        _expectOpenActions(tester, 'hdc', false);
        expect(
          find.text(language == 'zh' ? '未检测到工具' : 'Tool not detected'),
          findsOneWidget,
        );
        expect(
          tester.widget<OutlinedButton>(_control('hdc', 'choose')).onPressed,
          isNotNull,
        );
        expect(
          tester.widget<FilledButton>(_control('hdc', 'save')).onPressed,
          isNotNull,
        );
        expect(
          tester.widget<TextButton>(_control('hdc', 'reset')).onPressed,
          isNotNull,
        );
        await tester.tap(_control('hdc', 'open-directory'));
        await tester.tap(_control('hdc', 'open-terminal'));
        expect(opened, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
