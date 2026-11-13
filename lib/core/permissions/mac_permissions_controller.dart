import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mac_permission.dart';
import 'mac_permissions_service.dart';

final macPermissionsServiceProvider = Provider<MacPermissionsService>(
  (ref) => MacPermissionsService(),
);

final macPermissionsProvider =
    NotifierProvider.autoDispose<MacPermissionsController, MacPermissionsState>(
      MacPermissionsController.new,
    );

/// 串行用户动作与有版本号的刷新，避免旧查询覆盖申请完成后的状态。
class MacPermissionsController extends Notifier<MacPermissionsState> {
  int _revision = 0;

  @override
  MacPermissionsState build() => const MacPermissionsState();

  Future<void> refresh() async {
    final revision = ++_revision;
    state = MacPermissionsState(statuses: state.statuses, busy: state.busy);
    try {
      final statuses = await ref.read(macPermissionsServiceProvider).readAll();
      if (!ref.mounted || revision != _revision) return;
      state = MacPermissionsState(
        statuses: statuses,
        loading: false,
        busy: state.busy,
      );
    } catch (_) {
      if (!ref.mounted || revision != _revision) return;
      // 查询失败不保留上一次的“已授权”，以免用户误判撤销后的权限。
      state = MacPermissionsState(
        loading: false,
        busy: state.busy,
        errorKey: 'macPermissionReadFailed',
      );
    }
  }

  Future<void> request(MacPermission permission) async {
    if (state.loading ||
        state.busy != null ||
        !permission.supportsRequest ||
        state.statusFor(permission) != MacPermissionStatus.notDetermined) {
      return;
    }
    await _perform(permission, request: true);
  }

  Future<void> openSettings(MacPermission permission) async {
    if (state.loading || state.busy != null) return;
    await _perform(permission, request: false);
  }

  Future<void> _perform(
    MacPermission permission, {
    required bool request,
  }) async {
    ++_revision;
    state = MacPermissionsState(
      statuses: state.statuses,
      loading: false,
      busy: permission,
    );
    String? errorKey;
    try {
      final service = ref.read(macPermissionsServiceProvider);
      if (request) {
        await service.request(permission);
      } else {
        await service.openSettings(permission);
      }
    } catch (_) {
      errorKey = request
          ? 'macPermissionRequestFailed'
          : 'macPermissionOpenFailed';
    }
    if (!ref.mounted) return;
    // 设置窗口已打开并不表示权限已改变，仍以重新读取的系统结果为准。
    await refresh();
    if (!ref.mounted) return;
    state = MacPermissionsState(
      statuses: state.statuses,
      loading: state.loading,
      errorKey: errorKey ?? state.errorKey,
    );
  }
}
