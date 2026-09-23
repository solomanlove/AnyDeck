import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../files/remote_file.dart';
import 'device_tracking_providers.dart';
import 'service_providers.dart';

/// 远程文件列表目录查询参数请求对象。
class RemoteDirectoryRequest {
  const RemoteDirectoryRequest({required this.deviceId, required this.path});

  /// 目标设备 ID
  final String deviceId;

  /// 远程遍历的目标路径，如 `/sdcard/`
  final String path;

  @override
  bool operator ==(Object other) {
    return other is RemoteDirectoryRequest &&
        other.deviceId == deviceId &&
        other.path == path;
  }

  @override
  int get hashCode => Object.hash(deviceId, path);
}

/// 按设备与路径缓存的远程文件目录内容 Provider。
///
/// 依赖 [RemoteDirectoryRequest] 参数，设备离线时直接返回空列表。
final remoteFilesProvider = FutureProvider.autoDispose
    .family<List<RemoteFile>, RemoteDirectoryRequest>((ref, request) async {
      final isOnline = ref.watch(deviceOnlineProvider(request.deviceId));
      if (!isOnline) {
        return <RemoteFile>[];
      }
      return ref
          .watch(fileManagerServiceProvider)
          .listFiles(request.deviceId, request.path);
    });

/// 远程文件导航高级状态模型。
class FileNavigationState {
  const FileNavigationState({
    required this.currentPath,
    required this.history,
    required this.historyIndex,
    this.isEditingPath = false,
    this.showHiddenFiles = false,
    this.isGridView = false,
    this.sortColumn = 'name',
    this.sortAscending = true,
  });

  /// 当前所在的远程路径
  final String currentPath;

  /// 历史访问路径列表
  final List<String> history;

  /// 当前处于历史列表的指针索引
  final int historyIndex;

  /// 是否正在手动编辑路径输入框
  final bool isEditingPath;

  /// 是否展示以点开头的隐藏文件
  final bool showHiddenFiles;

  /// 是否为网格视图（false 为列表表格视图）
  final bool isGridView;

  /// 当前排序列，例如 'name', 'size', 'date'
  final String sortColumn;

  /// 排序是否为升序
  final bool sortAscending;

  /// 是否可以执行返回上一页
  bool get canGoBack => historyIndex > 0;

  /// 是否可以执行前进
  bool get canGoForward => historyIndex < history.length - 1;

  FileNavigationState copyWith({
    String? currentPath,
    List<String>? history,
    int? historyIndex,
    bool? isEditingPath,
    bool? showHiddenFiles,
    bool? isGridView,
    String? sortColumn,
    bool? sortAscending,
  }) {
    return FileNavigationState(
      currentPath: currentPath ?? this.currentPath,
      history: history ?? this.history,
      historyIndex: historyIndex ?? this.historyIndex,
      isEditingPath: isEditingPath ?? this.isEditingPath,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      isGridView: isGridView ?? this.isGridView,
      sortColumn: sortColumn ?? this.sortColumn,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }
}

/// 文件浏览器高级导航状态控制器 Provider。
final fileNavigationProvider =
    NotifierProvider<FileNavigationNotifier, FileNavigationState>(
      FileNavigationNotifier.new,
    );

/// 维护文件浏览器前进、后退、向上跳转、排序与展示模式。
class FileNavigationNotifier extends Notifier<FileNavigationState> {
  @override
  FileNavigationState build() {
    const initialPath = '/';
    return const FileNavigationState(
      currentPath: initialPath,
      history: [initialPath],
      historyIndex: 0,
    );
  }

  /// 导航到指定绝对路径
  void navigateTo(String path) {
    final normalized = _normalize(path);
    if (state.currentPath == normalized) return;

    final newHistory = state.history.sublist(0, state.historyIndex + 1);
    newHistory.add(normalized);

    state = state.copyWith(
      currentPath: normalized,
      history: newHistory,
      historyIndex: newHistory.length - 1,
      isEditingPath: false,
    );
  }

  /// 返回历史上一级目录
  void goBack() {
    if (!state.canGoBack) return;
    final newIndex = state.historyIndex - 1;
    state = state.copyWith(
      currentPath: state.history[newIndex],
      historyIndex: newIndex,
      isEditingPath: false,
    );
  }

  /// 前进到历史下一级目录
  void goForward() {
    if (!state.canGoForward) return;
    final newIndex = state.historyIndex + 1;
    state = state.copyWith(
      currentPath: state.history[newIndex],
      historyIndex: newIndex,
      isEditingPath: false,
    );
  }

  /// 向上跳转到父目录
  void goUp() {
    final path = state.currentPath;
    if (path == '/') return;

    final normalized = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final lastSlash = normalized.lastIndexOf('/');
    final parent = lastSlash == 0
        ? '/'
        : normalized.substring(0, lastSlash + 1);

    navigateTo(parent);
  }

  /// 切换当前路径编辑态
  void setEditingPath(bool editing) {
    state = state.copyWith(isEditingPath: editing);
  }

  /// 切换隐藏文件展示
  void toggleShowHiddenFiles() {
    state = state.copyWith(showHiddenFiles: !state.showHiddenFiles);
  }

  /// 切换网格与列表视图
  void setGridView(bool gridView) {
    state = state.copyWith(isGridView: gridView);
  }

  /// 点击列头切换排序
  void toggleSort(String column) {
    if (state.sortColumn == column) {
      state = state.copyWith(sortAscending: !state.sortAscending);
    } else {
      state = state.copyWith(sortColumn: column, sortAscending: true);
    }
  }

  /// 显式指定排序列与升降序
  void setSort(String column, bool ascending) {
    state = state.copyWith(sortColumn: column, sortAscending: ascending);
  }

  String _normalize(String path) {
    var p = path.trim();
    if (!p.startsWith('/')) {
      p = '/$p';
    }
    return p.endsWith('/') ? p : '$p/';
  }
}

/// 文件浏览器当前远程路径 Provider（兼容层，桥接到 [fileNavigationProvider]）。
final remotePathProvider = NotifierProvider<RemotePathNotifier, String>(
  RemotePathNotifier.new,
);

/// 兼容旧版调用的远程路径控制器。
class RemotePathNotifier extends Notifier<String> {
  @override
  String build() {
    return ref.watch(fileNavigationProvider).currentPath;
  }

  /// 打开当前路径下的子目录
  void open(String folderName) {
    ref
        .read(fileNavigationProvider.notifier)
        .navigateTo(_join(state, folderName));
  }

  /// 返回父目录
  void back() {
    ref.read(fileNavigationProvider.notifier).goUp();
  }

  /// 替换当前绝对路径
  void setPath(String path) {
    ref.read(fileNavigationProvider.notifier).navigateTo(path);
  }

  String _join(String base, String child) {
    final normalizedBase = base.endsWith('/') ? base : '$base/';
    return '$normalizedBase$child/';
  }
}

/// 文件列表实时搜索过滤关键字 Provider。
final fileFilterQueryProvider =
    NotifierProvider<FileFilterQueryNotifier, String>(
      FileFilterQueryNotifier.new,
    );

/// 维护文件列表本地搜索过滤关键字。
class FileFilterQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
  }
}
