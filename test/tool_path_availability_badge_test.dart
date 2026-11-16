import 'dart:io';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/process/tool_path_settings.dart';
import 'package:any_deck/features/overview/widget/tool_path_availability_badge.dart';
import 'package:any_deck/features/overview/widget/tool_path_setting_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 使用真实主题和文案验证环境提示，不调用系统安装器或任何工具命令。
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

Finder _badge(String tool) => find.byKey(ValueKey('tool-unavailable-$tool'));

/// 文件 stat 使用真实异步队列，Widget 的虚拟时钟不能代替文件 I/O。
Future<void> _completeProbe(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pumpAndSettle();
}

Future<File> _executable(Directory folder, String name) async {
  final file = await File(
    '${folder.path}/$name${Platform.isWindows ? '.exe' : ''}',
  ).writeAsString('AnyDeck test executable');
  if (!Platform.isWindows) {
    final result = await Process.run('/bin/chmod', ['700', file.path]);
    expect(result.exitCode, 0);
  }
  return file;
}

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync(
      'anydeck unavailable tools ',
    );
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  testWidgets('七种核心工具没有环境时均显示黄色缺失标识', (tester) async {
    await tester.pumpWidget(
      _harness(
        child: Column(
          children: [
            for (final tool in configurableToolNames)
              ToolPathAvailabilityBadge(toolName: tool, resolvedPath: tool),
          ],
        ),
      ),
    );
    await _completeProbe(tester);

    for (final tool in configurableToolNames) {
      expect(_badge(tool), findsOneWidget);
    }
    expect(find.text('未检测到工具'), findsNWidgets(configurableToolNames.length));
    expect(
      find.byIcon(Icons.warning_amber_rounded),
      findsNWidgets(configurableToolNames.length),
    );
    expect(tester.takeException(), isNull);
  });

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('缺失 HDC 的黄色标识在 $language $brightness 窄窗口可读且仍可配置', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var saved = false;
        await tester.pumpWidget(
          _harness(
            language: language,
            brightness: brightness,
            child: ToolPathSettingField(
              toolName: 'hdc',
              value: '',
              resolvedPath: 'hdc',
              onChanged: (_) async => saved = true,
              onOpen: (_) async {},
            ),
          ),
        );
        await _completeProbe(tester);

        expect(_badge('hdc'), findsOneWidget);
        final warningText = find.text(
          language == 'zh' ? '未检测到工具' : 'Tool not detected',
        );
        expect(warningText, findsOneWidget);
        final icon = tester.widget<Icon>(
          find.byIcon(Icons.warning_amber_rounded),
        );
        final theme = Theme.of(tester.element(warningText));
        expect(icon.color, theme.environmentWarningForeground);
        expect(
          tester.widget<Text>(warningText).style?.color,
          theme.environmentWarningForeground,
        );
        final decoration = tester.widget<Container>(_badge('hdc')).decoration;
        expect(
          (decoration as BoxDecoration).color,
          theme.environmentWarningBackground,
        );
        final foreground = theme.environmentWarningForeground
            .computeLuminance();
        final background = theme.environmentWarningBackground
            .computeLuminance();
        final contrast = foreground > background
            ? (foreground + 0.05) / (background + 0.05)
            : (background + 0.05) / (foreground + 0.05);
        expect(contrast, greaterThanOrEqualTo(4.5));
        expect(tester.takeException(), isNull);

        await tester.enterText(
          find.byKey(const ValueKey('tool-path-hdc')),
          '${temporary.path}/new hdc',
        );
        await tester.tap(find.byKey(const ValueKey('tool-save-hdc')));
        await tester.pump();
        expect(saved, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('未保存的可用路径不移除警告，保存与恢复默认按实际路径更新', (tester) async {
    late File executable;
    await tester.runAsync(() async {
      executable = await _executable(temporary, '新 HDC 工具');
    });
    final missing = '${temporary.path}/missing-hdc';
    var applied = '';
    await tester.pumpWidget(
      _harness(
        child: StatefulBuilder(
          builder: (context, update) => ToolPathSettingField(
            toolName: 'hdc',
            value: applied,
            resolvedPath: applied.isEmpty ? missing : applied,
            onChanged: (path) async => update(() => applied = path),
            onOpen: (_) async {},
          ),
        ),
      ),
    );
    await _completeProbe(tester);
    expect(_badge('hdc'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('tool-path-hdc')),
      executable.path,
    );
    await tester.pump();
    expect(_badge('hdc'), findsOneWidget);
    expect(applied, isEmpty);

    await tester.tap(find.byKey(const ValueKey('tool-save-hdc')));
    await tester.pump();
    await _completeProbe(tester);
    expect(applied, executable.path);
    expect(_badge('hdc'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tool-reset-hdc')));
    await tester.pump();
    await _completeProbe(tester);
    expect(applied, isEmpty);
    expect(_badge('hdc'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final lifecycle in [false, true]) {
    testWidgets('工具文件被删除后通过 ${lifecycle ? 'resumed' : 'revision'} 更新缺失标识', (
      tester,
    ) async {
      late File executable;
      await tester.runAsync(() async {
        executable = await _executable(temporary, 'custom ios');
      });
      var revision = 0;
      Widget content() => _harness(
        child: ToolPathAvailabilityBadge(
          toolName: 'ios',
          resolvedPath: executable.path,
          revision: revision,
        ),
      );
      await tester.pumpWidget(content());
      await _completeProbe(tester);
      expect(_badge('ios'), findsNothing);

      executable.deleteSync();
      if (lifecycle) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      } else {
        revision++;
        await tester.pumpWidget(content());
      }
      await _completeProbe(tester);
      expect(_badge('ios'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
