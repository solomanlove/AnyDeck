import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 桌面端开机自启服务，负责与原生登录项/LaunchAgents 交互。
class DesktopAutoStartService {
  DesktopAutoStartService._();

  static const _channel = MethodChannel('any_deck/autostart');
  static const _plistLabel = 'com.github.anydeck';

  /// 检查当前系统是否已开启开机自启。
  static Future<bool> isEnabled() async {
    if (kIsWeb || !Platform.isMacOS) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('isEnabled');
      if (result != null) return result;
    } on MissingPluginException {
      debugPrint('[DesktopAutoStartService] Native channel not registered, using fallback.');
    } catch (e) {
      debugPrint('[DesktopAutoStartService] isEnabled failed: $e');
    }

    // 兜底检测 LaunchAgent 配置文件
    return _checkLaunchAgentExists();
  }

  /// 开启或关闭开机自启。
  static Future<bool> setEnabled(bool enabled) async {
    if (kIsWeb || !Platform.isMacOS) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('setEnabled', enabled);
      if (result != null) return result;
    } on MissingPluginException {
      debugPrint('[DesktopAutoStartService] Native channel not registered, using fallback.');
    } catch (e) {
      debugPrint('[DesktopAutoStartService] setEnabled failed: $e');
    }

    // 兜底通过 Dart 直接写入或删除 ~/Library/LaunchAgents/com.github.anydeck.plist
    return _setLaunchAgentFallback(enabled);
  }

  /// 获取用户 LaunchAgent 配置文件路径。
  static File? get _launchAgentFile {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return null;
    return File('$home/Library/LaunchAgents/$_plistLabel.plist');
  }

  /// 兜底检测 LaunchAgent 是否存在。
  static bool _checkLaunchAgentExists() {
    try {
      final file = _launchAgentFile;
      return file != null && file.existsSync();
    } catch (e) {
      debugPrint('[DesktopAutoStartService] _checkLaunchAgentExists error: $e');
      return false;
    }
  }

  /// 兜底创建或删除 LaunchAgent 配置文件。
  static bool _setLaunchAgentFallback(bool enabled) {
    try {
      final file = _launchAgentFile;
      if (file == null) return false;

      if (enabled) {
        if (!file.parent.existsSync()) {
          file.parent.createSync(recursive: true);
        }

        // 解析当前可执行文件或 .app 包路径
        final exePath = Platform.resolvedExecutable;
        String appPath = exePath;
        if (exePath.contains('.app/Contents/MacOS/')) {
          appPath = exePath.substring(0, exePath.indexOf('.app') + 4);
        }

        final plistContent = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$_plistLabel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>$appPath</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
''';
        file.writeAsStringSync(plistContent, flush: true);
        return true;
      } else {
        if (file.existsSync()) {
          file.deleteSync();
        }
        return true;
      }
    } catch (e) {
      debugPrint('[DesktopAutoStartService] _setLaunchAgentFallback error: $e');
      return false;
    }
  }
}
