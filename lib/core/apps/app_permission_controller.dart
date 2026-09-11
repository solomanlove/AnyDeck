import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import 'adb_app_permission.dart';
import 'app_permission_service.dart';

/// 同一设备和应用的详情页、弹窗共享操作锁与设备回读状态。
final appPermissionControllerProvider = NotifierProvider.autoDispose
    .family<AppPermissionController, AppPermissionState, (String, String)>(
      AppPermissionController.new,
    );

/// 权限筛选仅影响展示，不改变批量撤销的作用范围。
enum AppPermissionFilter { all, runtime, install, unknown }

class AppPermissionState {
  const AppPermissionState({
    this.permissions = const [],
    this.loading = true,
    this.busy = false,
    this.error,
    this.userId,
    this.query = '',
    this.filter = AppPermissionFilter.all,
  });
  final List<AdbAppPermission> permissions;
  final bool loading;
  final bool busy;
  final String? error;
  final int? userId;
  final String query;
  final AppPermissionFilter filter;

  AppPermissionState copyWith({
    List<AdbAppPermission>? permissions,
    bool? loading,
    bool? busy,
    String? error,
    int? userId,
    String? query,
    AppPermissionFilter? filter,
  }) => AppPermissionState(
    permissions: permissions ?? this.permissions,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    error: error,
    userId: userId ?? this.userId,
    query: query ?? this.query,
    filter: filter ?? this.filter,
  );
}

/// 负责异步命令、防重复操作及回读；UI 不乐观伪造授权状态。
class AppPermissionController extends Notifier<AppPermissionState> {
  AppPermissionController(this.target);
  final (String, String) target;
  AppPermissionService get _service => ref.read(appPermissionServiceProvider);

  @override
  AppPermissionState build() {
    Future.microtask(refresh);
    return const AppPermissionState();
  }

  void search(String query) =>
      state = state.copyWith(query: query, error: state.error);
  void filter(AppPermissionFilter filter) =>
      state = state.copyWith(filter: filter, error: state.error);

  Future<void> refresh() async {
    if (!ref.mounted || state.busy) return;
    state = state.copyWith(loading: true);
    await _reload();
  }

  Future<void> _reload() async {
    try {
      final user = await _service.currentUserId(target.$1);
      final permissions = await _service.getPermissions(
        target.$1,
        target.$2,
        userId: user,
      );
      if (ref.mounted) {
        state = state.copyWith(
          permissions: permissions,
          userId: user,
          loading: false,
        );
      }
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(loading: false, error: error.toString());
      }
    }
  }

  Future<String?> toggle(AdbAppPermission permission, bool granted) async {
    if (state.busy ||
        state.loading ||
        state.error != null ||
        !permission.canChange) {
      return null;
    }
    final user = state.userId!;
    final service = _service;
    // 操作结束前保留锁，关闭后重开面板也不能交错执行命令。
    final operation = ref.keepAlive();
    state = state.copyWith(busy: true);
    String? error;
    try {
      final result = granted
          ? await service.grantPermission(
              target.$1,
              target.$2,
              permission.name,
              userId: user,
            )
          : await service.revokePermission(
              target.$1,
              target.$2,
              permission.name,
              userId: user,
            );
      if (!result.isSuccess) error = result.message;
      final permissions = await service.getPermissions(
        target.$1,
        target.$2,
        userId: user,
      );
      if (ref.mounted) state = state.copyWith(permissions: permissions);
    } catch (failure) {
      error = failure.toString();
      if (ref.mounted) state = state.copyWith(error: error);
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false, error: state.error);
      operation.close();
    }
    return error;
  }

  /// 确认弹窗期间也持有锁，防止单项修改和批量撤销交错。
  Future<PermissionRevokeResult?> revokeAll(
    Future<bool> Function() confirm,
  ) async {
    if (state.busy || state.loading || state.error != null) return null;
    final user = state.userId!;
    final service = _service;
    // 操作结束前保留锁，关闭后重开面板也不能交错执行命令。
    final operation = ref.keepAlive();
    state = state.copyWith(busy: true);
    try {
      if (!await confirm() || !ref.mounted) return null;
      final result = await service.revokeAllRuntimePermissionsDetailed(
        target.$1,
        target.$2,
        userId: user,
      );
      if (ref.mounted) state = state.copyWith(permissions: result.permissions);
      return result;
    } catch (error) {
      if (ref.mounted) state = state.copyWith(error: error.toString());
      return null;
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false, error: state.error);
      operation.close();
    }
  }
}
