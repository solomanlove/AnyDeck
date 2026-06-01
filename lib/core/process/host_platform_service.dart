import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// 宿主机系统平台服务，负责处理所有与宿主机 OS 交互的操作。
class HostPlatformService {
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
        final psCommand = 'Add-Type -AssemblyName System.Windows.Forms, System.Drawing; '
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
    try {
      if (Platform.isMacOS) {
        await Process.start('open', [directory.path]);
      } else if (Platform.isWindows) {
        await Process.start('explorer', [directory.path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [directory.path]);
      } else {
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Failed to open directory $dirPath: $e');
      return false;
    }
  }

  /// 使用宿主机默认程序打开指定文件。
  Future<bool> openFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      return false;
    }
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', file.path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [file.path]);
      } else {
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Failed to open file $filePath: $e');
      return false;
    }
  }

  /// 在指定目录下打开宿主机系统的命令行终端。
  Future<bool> openTerminal(String dirPath) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-a', 'Terminal', dirPath]);
      } else if (Platform.isWindows) {
        await Process.run('cmd.exe', ['/c', 'start', 'cmd.exe'], workingDirectory: dirPath);
      } else if (Platform.isLinux) {
        await Process.run('x-terminal-emulator', [], workingDirectory: dirPath);
      } else {
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Failed to open terminal in directory $dirPath: $e');
      return false;
    }
  }
}
