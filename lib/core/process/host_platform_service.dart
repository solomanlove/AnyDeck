import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'tool_terminal_launcher.dart';

/// 系统启动器注入点；测试无需打开真实文件管理器或终端。
typedef HostProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// 宿主机系统平台服务，负责处理所有与宿主机 OS 交互的操作。
class HostPlatformService {
  HostPlatformService({
    HostProcessStarter? processStarter,
    TargetPlatform? platform,
    Duration launchTimeout = const Duration(seconds: 15),
    Duration terminateTimeout = const Duration(seconds: 2),
    Duration startupGrace = const Duration(milliseconds: 300),
  }) : _startProcess = processStarter ?? _startHostProcess,
       _platform = platform ?? _hostPlatform,
       _launchTimeout = launchTimeout,
       _terminateTimeout = terminateTimeout,
       _startupGrace = startupGrace;

  final HostProcessStarter _startProcess;
  final TargetPlatform? _platform;
  final Duration _launchTimeout;
  final Duration _terminateTimeout;
  final Duration _startupGrace;

  static TargetPlatform? get _hostPlatform => Platform.isMacOS
      ? TargetPlatform.macOS
      : Platform.isWindows
      ? TargetPlatform.windows
      : Platform.isLinux
      ? TargetPlatform.linux
      : null;

  static Future<Process> _startHostProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) =>
      Process.start(executable, arguments, workingDirectory: workingDirectory);

  /// 用默认浏览器打开 HTTP(S) 链接；独立传参，避免查询参数被 Shell 解释。
  Future<bool> openWebUri(Uri uri) async {
    if (!['https', 'http'].contains(uri.scheme) || uri.host.isEmpty) {
      return false;
    }
    Process? process;
    StreamSubscription<List<int>>? output;
    StreamSubscription<List<int>>? errors;
    try {
      final String executable;
      final List<String> arguments;
      if (Platform.isMacOS) {
        executable = 'open';
        arguments = [uri.toString()];
      } else if (Platform.isWindows) {
        executable = 'rundll32.exe';
        arguments = ['url.dll,FileProtocolHandler', uri.toString()];
      } else if (Platform.isLinux) {
        executable = 'xdg-open';
        arguments = [uri.toString()];
      } else {
        return false;
      }
      process = await Process.start(executable, arguments);
      // 丢弃启动器输出，避免缓冲区阻塞，也不记录反馈内容。
      output = process.stdout.listen((_) {}, onError: (Object _) {});
      errors = process.stderr.listen((_) {}, onError: (Object _) {});
      return await process.exitCode.timeout(const Duration(seconds: 15)) == 0;
    } on TimeoutException {
      process?.kill();
      await process?.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process?.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      return false;
    } catch (_) {
      return false;
    } finally {
      await output?.cancel();
      await errors?.cancel();
    }
  }

  /// 为选定工具创建独立终端，短命令和工作目录都使用同一个可执行文件。
  Future<bool> openToolTerminal(String executable, String toolName) =>
      ToolTerminalLauncher(
        platform: _platform,
        launch: (command, arguments, {workingDirectory}) =>
            _launchHostApplication(
              command,
              arguments,
              workingDirectory: workingDirectory,
              acceptRunning: _platform == TargetPlatform.linux,
            ),
      ).open(executable, toolName);

  /// 将 PNG 图片字节复制到宿主机系统剪贴板。
  Future<bool> copyImageToClipboard(Uint8List bytes) async {
    try {
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/adb_screenshot_temp.png');
      await tempFile.writeAsBytes(bytes);

      if (Platform.isMacOS) {
        final result = await Process.run('osascript', [
          '-e',
          'set the clipboard to (read (POSIX file "${tempFile.path}") as «class PNGf»)',
        ]);
        return result.exitCode == 0;
      } else if (Platform.isWindows) {
        final psCommand =
            'Add-Type -AssemblyName System.Windows.Forms, System.Drawing; '
            '[System.Windows.Forms.Clipboard]::SetImage([System.Drawing.Image]::FromFile("${tempFile.path}"))';
        final result = await Process.run('powershell', ['-Command', psCommand]);
        return result.exitCode == 0;
      } else if (Platform.isLinux) {
        final result = await Process.run('xclip', [
          '-selection',
          'clipboard',
          '-t',
          'image/png',
          '-i',
          tempFile.path,
        ]);
        return result.exitCode == 0;
      }
      return false;
    } catch (e) {
      debugPrint('Failed to copy clipboard image: $e');
      return false;
    }
  }

  /// 在宿主机系统文件管理器中打开指定目录。
  Future<bool> openDirectory(String dirPath) async {
    final directory = Directory(dirPath);
    if (!directory.existsSync()) {
      return false;
    }
    final executable = switch (_platform) {
      TargetPlatform.macOS => 'open',
      TargetPlatform.windows => 'explorer',
      TargetPlatform.linux => 'xdg-open',
      _ => null,
    };
    if (executable == null) return false;
    return _launchHostApplication(executable, [
      directory.path,
    ], acceptRunning: _platform != TargetPlatform.macOS);
  }

  /// 使用宿主机默认程序打开指定文件。
  Future<bool> openFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      return false;
    }
    try {
      ProcessResult result;
      if (Platform.isMacOS) {
        result = await Process.run('open', [file.path]);
      } else if (Platform.isWindows) {
        // 避免通过 cmd /c 解释 Android 文件名中的 &, | 等 shell 字符。
        result = await Process.run('explorer', [file.path]);
      } else if (Platform.isLinux) {
        result = await Process.run('xdg-open', [file.path]);
      } else {
        return false;
      }
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('Failed to open file $filePath: $e');
      return false;
    }
  }

  /// 在指定目录下打开宿主机系统的命令行终端。
  Future<bool> openTerminal(String dirPath) async {
    if (!Directory(dirPath).existsSync()) return false;
    return switch (_platform) {
      TargetPlatform.macOS => _launchHostApplication('open', [
        '-a',
        'Terminal',
        dirPath,
      ]),
      TargetPlatform.windows => _launchHostApplication('cmd.exe', [
        '/c',
        'start',
        'cmd.exe',
      ], workingDirectory: dirPath),
      TargetPlatform.linux => _launchHostApplication(
        'x-terminal-emulator',
        [],
        workingDirectory: dirPath,
        acceptRunning: true,
      ),
      _ => false,
    };
  }

  /// 检查启动器退出结果；长驻系统应用只确认启动，避免关闭用户的终端或文件管理器。
  Future<bool> _launchHostApplication(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool acceptRunning = false,
  }) async {
    Process? process;
    StreamSubscription<List<int>>? output;
    StreamSubscription<List<int>>? errors;
    var applicationRunning = false;
    try {
      process = await _startProcess(
        executable,
        arguments,
        workingDirectory: workingDirectory,
      );
      output = process.stdout.listen((_) {}, onError: (Object _) {});
      errors = process.stderr.listen((_) {}, onError: (Object _) {});
      final code = await process.exitCode.timeout(
        acceptRunning ? _startupGrace : _launchTimeout,
        onTimeout: acceptRunning
            ? () {
                applicationRunning = true;
                return 0;
              }
            : null,
      );
      return code == 0;
    } on TimeoutException {
      process?.kill();
      await process?.exitCode.timeout(
        _terminateTimeout,
        onTimeout: () {
          process?.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      return false;
    } catch (error) {
      debugPrint('Failed to launch $executable: $error');
      return false;
    } finally {
      // 长驻系统应用交接后继续排空双流，直到其自然退出，避免管道阻塞或 SIGPIPE。
      if (!applicationRunning) {
        await output?.cancel();
        await errors?.cancel();
      }
    }
  }

  /// 获取实际的保存目录。如果用户设定的路径不存在或为空，则回退到 Downloads 目录，再回退到 Home 目录。
  String getSaveDirectory(String configuredPath) {
    if (configuredPath.isNotEmpty) {
      final dir = Directory(configuredPath);
      if (dir.existsSync()) {
        return dir.path;
      }
    }
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    if (home.isEmpty) return '.';
    final downloads = Directory('$home/Downloads');
    if (downloads.existsSync()) {
      return downloads.path;
    }
    return home;
  }

  /// 在保存目录中生成截图的唯一绝对路径。
  String generateScreenshotPath(String configuredPath, String deviceId) {
    final dir = getSaveDirectory(configuredPath);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    // 移除 deviceId 中不符合文件名规范的字符
    final safeDeviceId = deviceId.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return '$dir/screenshot_${safeDeviceId}_$timestamp.png';
  }

  /// 在保存目录中生成录屏视频的唯一绝对路径。
  String generateRecordPath(String configuredPath, String deviceId) {
    final dir = getSaveDirectory(configuredPath);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    // 移除 deviceId 中不符合文件名规范的字符
    final safeDeviceId = deviceId.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return '$dir/screenrecord_${safeDeviceId}_$timestamp.mp4';
  }
}
