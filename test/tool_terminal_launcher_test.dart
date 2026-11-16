import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/process/tool_terminal_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 以隔离 Shell 替代系统 Terminal，验证真实初始化内容和最终执行文件。
void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('anydeck_terminal_test_');
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
    for (final tool in ['adb', 'hdc', 'ios']) {
      test('$platform 的 $tool 终端使用所选改名文件，覆盖旧 PATH 与别名', () async {
        final home = await Directory('${temporary.path}/home').create();
        final selected = await Directory(
          "${temporary.path}/tool '空格\$(echo bad)",
        ).create();
        final old = await Directory('${temporary.path}/old').create();
        final binary = await File(
          '${selected.path}/custom tool',
        ).writeAsString('#!/bin/sh\nprintf "selected:%s\\n" "\$1"\n');
        await Process.run('/bin/chmod', ['700', binary.path]);
        await File(
          '${old.path}/$tool',
        ).writeAsString('#!/bin/sh\necho old-path\n');
        await Process.run('/bin/chmod', ['700', '${old.path}/$tool']);
        await File(
          '${home.path}/.bashrc',
        ).writeAsString("alias $tool='echo old-alias'\n");
        String? setupDirectory;
        String? result;
        final launcher = ToolTerminalLauncher(
          platform: platform,
          launch: (executable, arguments, {workingDirectory}) async {
            if (executable == '/bin/chmod') return true;
            final List<String> bashArguments;
            if (platform == TargetPlatform.macOS) {
              expect(executable, 'open');
              expect(arguments.take(2), ['-a', 'Terminal']);
              final command = File(arguments.last);
              setupDirectory = command.parent.path;
              bashArguments = [command.path];
            } else {
              expect(executable, 'x-terminal-emulator');
              expect(arguments.take(2), ['-e', '/bin/bash']);
              setupDirectory = File(arguments[3]).parent.path;
              bashArguments = arguments.skip(2).toList();
            }
            expect(workingDirectory, selected.path);
            final process = await Process.start(
              '/bin/bash',
              bashArguments,
              workingDirectory: workingDirectory,
              environment: {
                'HOME': home.path,
                'PATH': '${old.path}:/usr/bin:/bin',
              },
            );
            final output = process.stdout.transform(utf8.decoder).join();
            final errors = process.stderr.transform(utf8.decoder).join();
            process.stdin.writeln('$tool version');
            if (tool == 'ios') process.stdin.writeln('go-ios version');
            process.stdin.writeln('pwd');
            process.stdin.writeln('exit');
            await process.stdin.close();
            try {
              expect(
                await process.exitCode.timeout(const Duration(seconds: 5)),
                0,
              );
              result = await output;
              await errors;
              return true;
            } finally {
              process.kill(ProcessSignal.sigkill);
            }
          },
        );
        expect(await launcher.open(binary.path, tool), isTrue);
        expect(result, contains('selected:version'));
        expect(result, isNot(contains('old-path')));
        expect(result, isNot(contains('old-alias')));
        if (tool == 'ios') {
          expect(RegExp('selected:version').allMatches(result!), hasLength(2));
        }
        expect(result, contains(selected.path));
        expect(Directory(setupDirectory!).existsSync(), isFalse);
      }, skip: Platform.isWindows);
    }
  }

  test('Windows 终端传递准确目录并为改名文件设置短命令', () async {
    final folder = await Directory(
      "${temporary.path}/中文tool ' & %PATH% \$Tools",
    ).create();
    final file = await File('${folder.path}/custom\$1.exe').create();
    String? setupDirectory;
    final launcher = ToolTerminalLauncher(
      platform: TargetPlatform.windows,
      launch: (executable, arguments, {workingDirectory}) async {
        expect(executable, 'powershell.exe');
        expect(arguments.take(3), [
          '-NoProfile',
          '-NonInteractive',
          '-EncodedCommand',
        ]);
        final bytes = base64Decode(arguments.last);
        final script = String.fromCharCodes([
          for (var i = 0; i < bytes.length; i += 2)
            bytes[i] | bytes[i + 1] << 8,
        ]);
        final match = RegExp(
          r"\$env:ANYDECK_TOOL_INIT='((?:[^']|'')*)';",
        ).firstMatch(script)!;
        final setup = File(match[1]!.replaceAll("''", "'"));
        expect(workingDirectory, file.parent.path);
        expect(
          script,
          contains(
            "-WorkingDirectory '${file.parent.path.replaceAll("'", "''")}'",
          ),
        );
        expect(script, contains('/k ""%ANYDECK_TOOL_INIT%""'));
        setupDirectory = setup.parent.path;
        final text = await setup.readAsString();
        expect(text, contains('chcp 65001 >nul'));
        expect(
          text,
          contains(
            'set "ANYDECK_TOOL_EXECUTABLE=${file.path.replaceAll('%', '%%')}"',
          ),
        );
        expect(text, contains('doskey adb="%%ANYDECK_TOOL_EXECUTABLE%%" \$*'));
        expect(
          text,
          contains(
            'set "PATH=${file.parent.path.replaceAll('%', '%%')};%PATH%"',
          ),
        );
        return false;
      },
    );
    expect(await launcher.open(file.path, 'adb'), isFalse);
    expect(Directory(setupDirectory!).existsSync(), isFalse);
  });

  test('文件缺失和非法工具名称不启动任何程序', () async {
    final launcher = ToolTerminalLauncher(
      launch: (_, _, {workingDirectory}) async => fail('不应启动'),
    );
    expect(await launcher.open('${temporary.path}/missing', 'adb'), isFalse);
    expect(await launcher.open('/tmp/adb', 'adb; echo bad'), isFalse);
  });
}
