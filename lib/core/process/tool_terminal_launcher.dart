import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 系统终端启动器由宿主服务提供；测试可替换它而无需打开真实窗口。
typedef ToolTerminalLaunch =
    Future<bool> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// 为 Linux / Windows 打开选定 CLI 的终端，将短命令绑定到准确文件。
///
/// [launch] 负责系统启动器的退出码与超时回收；[platform] 可替换宿主平台。
/// 临时初始化文件只包含路径、别名和环境配置，不会自动运行用户选中的程序。
class ToolTerminalLauncher {
  const ToolTerminalLauncher({required this.launch, this.platform});

  final ToolTerminalLaunch launch;
  final TargetPlatform? platform;

  Future<bool> open(String executable, String toolName) async {
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_-]*$').hasMatch(toolName)) return false;
    final file = File(executable);
    if (!file.isAbsolute || !await file.exists()) return false;
    final target = platform ?? defaultTargetPlatform;
    if (![TargetPlatform.linux, TargetPlatform.windows].contains(target)) {
      return false;
    }
    final directory = await Directory.systemTemp.createTemp(
      'anydeck_tool_terminal_',
    );
    var accepted = false;
    try {
      final names = toolName == 'ios' || toolName == 'go-ios'
          ? ['ios', 'go-ios']
          : [toolName];
      final isWindows = target == TargetPlatform.windows;
      final setup = File(
        '${directory.path}/init.${isWindows ? 'cmd' : 'bash'}',
      );
      await setup.writeAsString(
        isWindows
            ? _windowsSetup(file, names, directory)
            : _bashSetup(file, names, directory),
      );
      final cwd = file.parent.path;
      switch (target) {
        case TargetPlatform.linux:
          accepted = await launch('x-terminal-emulator', [
            '-e',
            '/bin/bash',
            '--rcfile',
            setup.path,
            '-i',
          ], workingDirectory: cwd);
        case TargetPlatform.windows:
          // 工作目录不进入 cmd 语法，避免空格、& 和 % 被启动命令解释。
          final script =
              '\$env:ANYDECK_TOOL_INIT=${_powerShellQuote(setup.path)}; '
              'Start-Process -FilePath \$env:ComSpec '
              '-WorkingDirectory ${_powerShellQuote(cwd)} '
              '-ArgumentList \'/d /v:off /s /k ""%ANYDECK_TOOL_INIT%""\' '
              '-ErrorAction Stop';
          final bytes = [
            for (final unit in script.codeUnits) ...[unit & 255, unit >> 8],
          ];
          accepted = await launch('powershell.exe', [
            '-NoProfile',
            '-NonInteractive',
            '-EncodedCommand',
            base64Encode(bytes),
          ], workingDirectory: cwd);
        default:
          break;
      }
      return accepted;
    } finally {
      // 成功后由新 Shell 读取完初始化文件时清理，失败则立即回收。
      if (!accepted && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  String _bashSetup(File file, List<String> names, Directory temporary) => [
    // 保留用户常用配置，再覆盖本工具，避免用户原有 alias 抢占选定路径。
    r'if [ -f "$HOME/.bashrc" ]; then . "$HOME/.bashrc"; fi',
    'cd -- ${_shellQuote(file.parent.path)}',
    'export PATH=${_shellQuote(file.parent.path)}:"\$PATH"',
    for (final name in names)
      'alias $name=${_shellQuote(_shellQuote(file.path))}',
    'command rm -rf -- ${_shellQuote(temporary.path)}',
    '',
  ].join('\n');

  String _windowsSetup(File file, List<String> names, Directory temporary) => [
    '@echo off',
    'chcp 65001 >nul',
    'cd /d "${_batchPath(file.parent.path)}"',
    'set "PATH=${_batchPath(file.parent.path)};%PATH%"',
    // 文件名不直接进入 DOSKEY 宏，避免路径中的 $T / $1 / % 被二次解释。
    'set "ANYDECK_TOOL_EXECUTABLE=${_batchPath(file.path)}"',
    for (final name in names) 'doskey $name="%%ANYDECK_TOOL_EXECUTABLE%%" \$*',
    '(del "%~f0" & rmdir "${_batchPath(temporary.path)}")',
    '',
  ].join('\r\n');

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", "'\\''")}'";
  static String _batchPath(String value) => value.replaceAll('%', '%%');
  static String _powerShellQuote(String value) =>
      "'${value.replaceAll("'", "''")}'";
}
