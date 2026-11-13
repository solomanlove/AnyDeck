import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 登录项状态区分已注册、待批准与实际可运行，不将注册完成视为已启用。
enum DesktopAutoStartStatus {
  enabled,
  disabled,
  requiresApproval,
  manual,
  unavailable,
  unknown;

  static DesktopAutoStartStatus parse(Object? value) => values.firstWhere(
    (status) => status.name == value,
    orElse: () => unknown,
  );
}

/// 桌面端开机自启服务，所有注册与旧系统 LaunchAgent 操作均由原生端负责。
///
/// registerCancellation 由调用方绑定取消回调，并返回解除绑定的函数；
/// 例如传入 ref.onDispose，确保等待随所属 Provider 结束且不积累回调。
class DesktopAutoStartService {
  DesktopAutoStartService._();

  static const _channel = MethodChannel('any_deck/autostart');
  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static Future<bool> isEnabled() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } catch (error) {
      debugPrint('[DesktopAutoStartService] isEnabled failed: $error');
      return false;
    }
  }

  /// true 表示注册/移除完成，是否需要批准仍以 status 查询为准。
  static Future<bool> setEnabled(
    bool enabled, {
    VoidCallback Function(VoidCallback)? registerCancellation,
  }) async {
    if (!_supported) return false;
    return await _call<bool>(
          'setEnabled',
          arguments: enabled,
          registerCancellation: registerCancellation,
        ) ??
        false;
  }

  static Future<DesktopAutoStartStatus> status({
    VoidCallback Function(VoidCallback)? registerCancellation,
  }) async {
    if (!_supported) return DesktopAutoStartStatus.unavailable;
    final result = await _call<Object?>(
      'status',
      registerCancellation: registerCancellation,
    );
    return DesktopAutoStartStatus.parse(result);
  }

  /// 系统设置打开成功不表示用户已批准；功能入口返回前台后重新查询。
  static Future<void> openSettings({
    VoidCallback Function(VoidCallback)? registerCancellation,
  }) async {
    if (!_supported) throw PlatformException(code: 'unsupported_platform');
    await _call<void>(
      'openSettings',
      registerCancellation: registerCancellation,
    );
  }

  /// 原生调用无法取消；所属 Provider 销毁时结束等待并取消 Timer，忽略迟到回调。
  static Future<T?> _call<T>(
    String method, {
    Object? arguments,
    VoidCallback Function(VoidCallback)? registerCancellation,
  }) {
    final result = Completer<T?>();
    final timer = Timer(const Duration(seconds: 10), () {
      if (!result.isCompleted) result.completeError(TimeoutException(method));
    });
    final removeCancellation = registerCancellation?.call(() {
      timer.cancel();
      if (!result.isCompleted) {
        result.completeError(StateError('Autostart owner disposed'));
      }
    });
    _channel
        .invokeMethod<T>(method, arguments)
        .then(
          (value) {
            if (!result.isCompleted) result.complete(value);
          },
          onError: (Object error, StackTrace stack) {
            if (!result.isCompleted) result.completeError(error, stack);
          },
        );
    return result.future.whenComplete(() {
      timer.cancel();
      removeCancellation?.call();
    });
  }
}
