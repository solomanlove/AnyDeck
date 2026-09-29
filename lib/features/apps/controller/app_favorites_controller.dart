import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 管理收藏应用（✨）的持久化控制器。
class AppFavoritesNotifier extends AsyncNotifier<Set<String>> {
  AppFavoritesNotifier({String storageKey = 'apps.favoritePackages.v1'})
      : _key = storageKey;

  // 默认保留 Android 的存储位置，其他平台可使用独立命名空间。
  final String _key;

  @override
  Future<Set<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    return list.toSet();
  }

  /// 切换指定包名的收藏状态（收藏/取消收藏）。
  Future<void> toggle(String packageName) async {
    final current = state.value ?? <String>{};
    final updated = Set<String>.from(current);
    if (updated.contains(packageName)) {
      updated.remove(packageName);
    } else {
      updated.add(packageName);
    }
    state = AsyncData(updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, updated.toList());
  }

  /// 检查指定包名是否已被收藏。
  bool isFavorite(String packageName) {
    return (state.value ?? const <String>{}).contains(packageName);
  }

  /// 清空所有已收藏应用。
  Future<void> clear() async {
    state = const AsyncData(<String>{});
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// 提供全局应用收藏状态的 Provider。
final appFavoritesProvider =
    AsyncNotifierProvider<AppFavoritesNotifier, Set<String>>(
  AppFavoritesNotifier.new,
);
