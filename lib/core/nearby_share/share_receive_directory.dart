import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/settings/harmony_share_preference_keys.dart';

/// 接收根目录解析与显式选择时的可写性检查；失效的自定义目录不静默回退。
abstract final class ShareReceiveDirectory {
  static void validatePath(String value) {
    if (value.isNotEmpty &&
        (!value.startsWith('/') ||
            value.contains('\u0000') ||
            value.length > 4096)) {
      throw const FormatException('Invalid receive directory');
    }
  }

  static Future<Directory?> resolve() async {
    final prefs = await SharedPreferences.getInstance();
    return resolvePath(
      prefs.getString(HarmonySharePreferenceKeys.receiveDirectory) ?? '',
    );
  }

  /// 测试可注入 Downloads 解析，不访问真实用户目录。
  static Future<Directory?> resolvePath(
    String path, {
    Future<Directory?> Function()? downloads,
  }) async {
    validatePath(path);
    if (path.isEmpty) return (downloads ?? getDownloadsDirectory)();
    final folder = Directory(path);
    if (!await folder.exists()) {
      throw FileSystemException('Receive directory unavailable', path);
    }
    return folder;
  }

  static Future<void> checkWritable(String path) async {
    final folder = await resolvePath(path);
    if (folder == null) {
      throw const FileSystemException('Receive directory unavailable');
    }
    final probe = await folder.createTemp('.anydeck-write-check-');
    try {
      await File('${probe.path}/probe').writeAsBytes(const [0], flush: true);
    } finally {
      await probe.delete(recursive: true);
    }
  }
}
