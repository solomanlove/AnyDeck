import 'dart:async';

import '../adb/adb_result.dart';
import '../adb/adb_service.dart';
import 'adb_app_permission.dart';

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
    if (!result.isSuccess) {
      return 0;
    }
    return int.tryParse(result.stdout.trim()) ?? 0;
  }

  /// 获取设备上指定应用声明的所有权限及其授权状态。
  Future<List<AdbAppPermission>> getPermissions(
    String deviceId,
    String packageName,
  ) async {
    final currentUser = await _currentUserId(deviceId);
    final result = await _adb.shellArgs(
      deviceId,
      ['dumpsys', 'package', packageName],
      timeout: _metadataTimeout,
    );
    if (!result.isSuccess) {
      throw Exception(result.message);
    }
    return _parsePermissions(result.stdout, currentUser);
  }

  /// 授予运行时权限。
  Future<AdbResult> grantPermission(
    String deviceId,
    String packageName,
    String permission,
  ) {
    return _adb.shellArgs(deviceId, ['pm', 'grant', packageName, permission]);
  }

  /// 撤销/收回运行时权限。
  Future<AdbResult> revokePermission(
    String deviceId,
    String packageName,
    String permission,
  ) {
    return _adb.shellArgs(deviceId, ['pm', 'revoke', packageName, permission]);
  }

  /// 解析 dumpsys package 的输出，提取权限列表及状态。
  List<AdbAppPermission> _parsePermissions(String output, int currentUserId) {
    final permissionsMap = <String, AdbAppPermission>{};
    final lines = output.split('\n');
    final requested = <String>{};

    var inRequestedBlock = false;
    var inInstallBlock = false;
    var inActiveUserBlock = false;
    var inRuntimeBlock = false;

    final activeUserHeader = 'User $currentUserId:';

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      final leadingSpaces = line.length - line.trimLeft().length;

      // 4个或更少空格的缩进通常标志着主要区块的切换
      if (leadingSpaces <= 4) {
        inRequestedBlock = false;
        inInstallBlock = false;
        inRuntimeBlock = false;

        if (trimmed.startsWith('requested permissions:')) {
          inRequestedBlock = true;
          continue;
        } else if (trimmed.startsWith('install permissions:')) {
          inInstallBlock = true;
          continue;
        } else if (trimmed.startsWith('User ')) {
          inActiveUserBlock = trimmed.startsWith(activeUserHeader);
          continue;
        }
      }

      if (inActiveUserBlock && leadingSpaces == 6) {
        inRuntimeBlock = trimmed.startsWith('runtime permissions:');
        if (inRuntimeBlock) continue;
      }

      if (inRequestedBlock) {
        if (trimmed.startsWith('android.permission.') || trimmed.contains('.')) {
          requested.add(trimmed);
        }
      } else if (inInstallBlock && leadingSpaces >= 6) {
        final colonIndex = trimmed.indexOf(':');
        if (colonIndex != -1) {
          final name = trimmed.substring(0, colonIndex).trim();
          if (name.contains('.')) {
            final rest = trimmed.substring(colonIndex + 1);
            final granted = rest.contains('granted=true');
            permissionsMap[name] = AdbAppPermission(
              name: name,
              granted: granted,
              isRuntime: false,
            );
          }
        }
      } else if (inActiveUserBlock && inRuntimeBlock && leadingSpaces >= 8) {
        final colonIndex = trimmed.indexOf(':');
        if (colonIndex != -1) {
          final name = trimmed.substring(0, colonIndex).trim();
          if (name.contains('.')) {
            final rest = trimmed.substring(colonIndex + 1);
            final granted = rest.contains('granted=true');
            permissionsMap[name] = AdbAppPermission(
              name: name,
              granted: granted,
              isRuntime: true,
            );
          }
        }
      }
    }

    // 补充在 requested permissions 中声明，但不在 install/runtime blocks 中体现的权限
    for (final perm in requested) {
      if (!permissionsMap.containsKey(perm)) {
        permissionsMap[perm] = AdbAppPermission(
          name: perm,
          granted: false,
          isRuntime: false,
        );
      }
    }

    final list = permissionsMap.values.toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }
}
