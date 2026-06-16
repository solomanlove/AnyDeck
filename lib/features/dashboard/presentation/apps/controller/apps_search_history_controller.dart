import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 管理应用列表搜索过滤的历史记录控制器。
class AppsSearchHistoryNotifier extends AsyncNotifier<List<String>> {
  static const _key = 'apps_search_history';

  @override
  Future<List<String>> build() async {
    // 异步加载 SharedPreferences 中的历史记录列表
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  /// 添加一条历史记录，若已存在则移到最前，并限制最多保存 10 条。
  Future<void> add(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;

    final current = state.value ?? [];
    final updated = List<String>.from(current)
      ..remove(cleanQuery)
      ..insert(0, cleanQuery);

    if (updated.length > 10) {
      updated.removeRange(10, updated.length);
    }

    state = AsyncData(updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, updated);
  }

  /// 移除指定的一条历史记录。
  Future<void> remove(String query) async {
    final current = state.value ?? [];
    final updated = List<String>.from(current)..remove(query);

    state = AsyncData(updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, updated);
  }

  /// 清空所有的历史记录。
  Future<void> clear() async {
    state = const AsyncData([]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// 提供应用搜索历史状态的 Provider。
final appsSearchHistoryProvider =
    AsyncNotifierProvider<AppsSearchHistoryNotifier, List<String>>(
  AppsSearchHistoryNotifier.new,
);
