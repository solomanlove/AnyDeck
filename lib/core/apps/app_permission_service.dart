import '../adb/adb_result.dart';
import '../adb/adb_service.dart';
import 'adb_app_permission.dart';
import 'app_permission_parser.dart';

/// 管理应用权限（获取权限列表、授予/撤回运行时权限）的 ADB 服务。
class AppPermissionService {
  AppPermissionService(this._adb);

  final AdbService _adb;
  static const _metadataTimeout = Duration(seconds: 10);
  static const _quickTimeout = Duration(seconds: 8);

  Future<int> _currentUserId(String deviceId) async {
    final result = await _adb.shellArgs(deviceId, [
      'am',
      'get-current-user',
    ], timeout: _quickTimeout);
    final id = int.tryParse(result.stdout.trim());
    if (!result.isSuccess || id == null || id < 0) {
      throw Exception(result.message);
    }
    return id;
  }

  /// 获取设备上指定应用声明的所有权限及其授权状态。
  Future<List<AdbAppPermission>> getPermissions(
    String deviceId,
    String packageName, {
    int? userId,
  }) async {
    final currentUser = userId ?? await _currentUserId(deviceId);
    final result = await _adb.shellArgs(deviceId, [
      'dumpsys',
      'package',
      packageName,
    ], timeout: _metadataTimeout);
    if (!result.isSuccess) {
      throw Exception(result.message);
    }
    final types = await _adb.shellArgs(deviceId, [
      'pm',
      'list',
      'permissions',
      '-f',
    ], timeout: _metadataTimeout);
    return parseAppPermissions(
      result.stdout,
      currentUser,
      permissionTypes: types.isSuccess
          ? parsePermissionTypes(types.stdout)
          : const {},
    );
  }

  /// 授予或撤销时显式指定用户，避免默认作用于 user 0。
  Future<AdbResult> grantPermission(
    String deviceId,
    String packageName,
    String permission, {
    int? userId,
  }) async => _changePermission(
    deviceId,
    packageName,
    permission,
    true,
    userId ?? await _currentUserId(deviceId),
  );

  Future<AdbResult> revokePermission(
    String deviceId,
    String packageName,
    String permission, {
    int? userId,
  }) async => _changePermission(
    deviceId,
    packageName,
    permission,
    false,
    userId ?? await _currentUserId(deviceId),
  );

  Future<AdbResult> _changePermission(
    String deviceId,
    String packageName,
    String permission,
    bool grant,
    int userId,
  ) => _adb.shellArgs(deviceId, [
    'pm',
    grant ? 'grant' : 'revoke',
    '--user',
    '$userId',
    packageName,
    permission,
  ], timeout: _quickTimeout);

  /// 固定一次操作的用户身份；读取、修改、回读必须使用同一 userId。
  Future<int> currentUserId(String deviceId) => _currentUserId(deviceId);

  /// 兼容既有调用方，详细结果由批量接口提供。
  Future<int> revokeAllRuntimePermissions(
    String deviceId,
    String packageName,
  ) async {
    return (await revokeAllRuntimePermissionsDetailed(
      deviceId,
      packageName,
    )).succeeded;
  }

  /// 串行撤销所有已授予的动态权限，逐项保留失败原因并回读真实状态。
  Future<PermissionRevokeResult> revokeAllRuntimePermissionsDetailed(
    String deviceId,
    String packageName, {
    int? userId,
  }) async {
    final user = userId ?? await _currentUserId(deviceId);
    final before = await getPermissions(deviceId, packageName, userId: user);
    final targets = before.where((p) => p.isRuntime && p.granted).toList();
    final errors = <String, String>{};
    for (final permission in targets) {
      try {
        final result = await revokePermission(
          deviceId,
          packageName,
          permission.name,
          userId: user,
        );
        if (!result.isSuccess) errors[permission.name] = result.message;
      } catch (error) {
        errors[permission.name] = error.toString();
      }
    }
    final after = await getPermissions(deviceId, packageName, userId: user);
    final revoked = after
        .where((p) => p.isRuntime && !p.granted)
        .map((p) => p.name)
        .toSet();
    // 组权限联动可能使后续命令报错，以回读结果判定是否真正撤销。
    final failed = targets
        .where((p) => !revoked.contains(p.name))
        .map((p) => p.name)
        .toList();
    return PermissionRevokeResult(
      permissions: after,
      total: targets.length,
      failedPermissions: failed,
      errors: errors,
    );
  }

  /// 一键授予应用声明的所有运行时权限。
  /// 返回成功授予的权限数量。
  Future<int> grantAllRuntimePermissions(
    String deviceId,
    String packageName,
  ) async {
    final permissions = await getPermissions(deviceId, packageName);
    final ungrantedRuntime = permissions
        .where((p) => p.isRuntime && !p.granted)
        .toList();

    var count = 0;
    for (final perm in ungrantedRuntime) {
      final result = await grantPermission(deviceId, packageName, perm.name);
      if (result.isSuccess) {
        count++;
      }
    }
    return count;
  }
}

/// 批量撤销的回读结果，部分失败不能被报告为全部成功。
class PermissionRevokeResult {
  const PermissionRevokeResult({
    required this.permissions,
    required this.total,
    required this.failedPermissions,
    required this.errors,
  });
  final List<AdbAppPermission> permissions;
  final int total;
  final List<String> failedPermissions;
  final Map<String, String> errors;
  int get succeeded => total - failedPermissions.length;
}
