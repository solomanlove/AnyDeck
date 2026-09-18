import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 管理单个 Tab 的搜索历史，最多保留 10 条已提交记录。
abstract class DashboardSearchHistoryNotifier
    extends AsyncNotifier<List<String>> {
  String get key;

  @override
  Future<List<String>> build() async {
    // 异步加载 SharedPreferences 中的历史记录列表
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(key) ?? [];
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
    await prefs.setStringList(key, updated);
  }

  /// 移除指定的一条历史记录。
  Future<void> remove(String query) async {
    final current = state.value ?? [];
    final updated = List<String>.from(current)..remove(query);

    state = AsyncData(updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, updated);
  }

  /// 清空所有的历史记录。
  Future<void> clear() async {
    state = const AsyncData([]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}

/// 保留已有应用搜索记录使用的持久化 key。
class AppsSearchHistoryNotifier extends DashboardSearchHistoryNotifier {
  @override
  String get key => 'apps_search_history';
}

/// 进程 Tab 搜索历史。
class ProcessesSearchHistoryNotifier extends DashboardSearchHistoryNotifier {
  @override
  String get key => 'processes_search_history';
}

/// 文件 Tab 搜索历史，Android 与 Harmony 页面共用。
class FilesSearchHistoryNotifier extends DashboardSearchHistoryNotifier {
  @override
  String get key => 'files_search_history';
}

final appsSearchHistoryProvider =
    AsyncNotifierProvider<AppsSearchHistoryNotifier, List<String>>(
      AppsSearchHistoryNotifier.new,
    );

final processesSearchHistoryProvider =
    AsyncNotifierProvider<ProcessesSearchHistoryNotifier, List<String>>(
      ProcessesSearchHistoryNotifier.new,
    );

final filesSearchHistoryProvider =
    AsyncNotifierProvider<FilesSearchHistoryNotifier, List<String>>(
      FilesSearchHistoryNotifier.new,
    );
