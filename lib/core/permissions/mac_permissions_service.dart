import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'mac_permission.dart';

/// 只读查询不发起授权；用户需要手动批准时提供系统设置跳转。
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
