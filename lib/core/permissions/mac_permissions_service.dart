import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'mac_permission.dart';

/// 只读查询不会触发权限弹窗；申请和设置跳转必须来自显式用户操作。
class MacPermissionsService {
  MacPermissionsService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('anydeck/macos_permissions');

  final MethodChannel _channel;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  Future<Map<MacPermission, MacPermissionStatus>> readAll() async {
    if (!isSupported) {
      return {
        for (final permission in MacPermission.values)
          permission: MacPermissionStatus.unsupported,
      };
    }
    final response = await _channel
        .invokeMethod<Object?>('readAll')
        .timeout(const Duration(seconds: 10));
    if (response is! Map) {
      throw PlatformException(code: 'invalid_permission_response');
    }
    return Map.unmodifiable({
      for (final permission in MacPermission.values)
        permission: MacPermissionStatus.parse(response[permission.name]),
    });
  }

  Future<void> request(MacPermission permission) async {
    _requireMacOS();
    if (!permission.supportsRequest) {
      throw ArgumentError.value(permission, 'permission');
    }
    // 原生请求最多等待 60 秒；系统弹窗超时后仍可通过刷新读取最终结果。
    await _channel
        .invokeMethod<void>('request', {'permission': permission.name})
        .timeout(const Duration(seconds: 75));
  }

  Future<void> openSettings(MacPermission permission) async {
    _requireMacOS();
    await _channel
        .invokeMethod<void>('openSettings', {'permission': permission.name})
        .timeout(const Duration(seconds: 10));
  }

  void _requireMacOS() {
    if (!isSupported) throw PlatformException(code: 'unsupported_platform');
  }
}
