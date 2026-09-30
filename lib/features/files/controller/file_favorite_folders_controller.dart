import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 添加常用文件夹时的结果，用于区分重复和数量上限。
enum FileFavoriteAddResult { added, duplicate, limitReached }

/// 按设备保存 Files Tab 的自定义常用文件夹。
class FileFavoriteFoldersNotifier
    extends AsyncNotifier<Map<String, List<String>>> {
  static const _preferencesKey = 'files.favoriteFolders.v1';
  static const _maxFoldersPerDevice = 20;

  @override
  Future<Map<String, List<String>>> build() async {
    final preferences = await SharedPreferences.getInstance();
    final rawValue = preferences.getString(_preferencesKey);
    if (rawValue == null || rawValue.isEmpty) return {};

    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(rawValue));
      return decoded.map(
        (deviceId, paths) => MapEntry(
          deviceId,
          List<String>.from(paths as List).map(_normalizePath).toList(),
        ),
      );
    } catch (_) {
      // 忽略旧版本或损坏的本地数据，避免影响文件浏览器正常使用。
      return {};
    }
  }

  /// 把当前远程目录添加到指定设备的常用文件夹。
  Future<FileFavoriteAddResult> add(String deviceId, String path) async {
    final current = state.value ?? const <String, List<String>>{};
    final normalizedPath = _normalizePath(path);
    final devicePaths = List<String>.from(current[deviceId] ?? const []);
    if (devicePaths.contains(normalizedPath)) {
      return FileFavoriteAddResult.duplicate;
    }
    if (devicePaths.length >= _maxFoldersPerDevice) {
      return FileFavoriteAddResult.limitReached;
    }

    devicePaths.add(normalizedPath);
    final updated = Map<String, List<String>>.from(current)
      ..[deviceId] = devicePaths;
    state = AsyncData(updated);
    await _persist(updated);
    return FileFavoriteAddResult.added;
  }

  /// 删除指定设备下的一个常用文件夹。
  Future<void> remove(String deviceId, String path) async {
    final current = state.value ?? const <String, List<String>>{};
    final devicePaths = List<String>.from(current[deviceId] ?? const [])
      ..remove(_normalizePath(path));
    final updated = Map<String, List<String>>.from(current);
    if (devicePaths.isEmpty) {
      updated.remove(deviceId);
    } else {
      updated[deviceId] = devicePaths;
    }
    state = AsyncData(updated);
    await _persist(updated);
  }

  /// 清除指定设备下的所有常用文件夹配置。
  Future<void> clearDevice(String deviceId) async {
    final current = state.value ?? const <String, List<String>>{};
    if (!current.containsKey(deviceId)) return;
    final updated = Map<String, List<String>>.from(current)..remove(deviceId);
    state = AsyncData(updated);
    await _persist(updated);
  }

  Future<void> _persist(Map<String, List<String>> value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferencesKey, jsonEncode(value));
  }

  static String _normalizePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty || trimmed == '/') return '/';
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}

/// 提供所有设备的常用文件夹，UI 按当前 deviceId 读取对应列表。
final fileFavoriteFoldersProvider =
    AsyncNotifierProvider<
      FileFavoriteFoldersNotifier,
      Map<String, List<String>>
    >(FileFavoriteFoldersNotifier.new);
