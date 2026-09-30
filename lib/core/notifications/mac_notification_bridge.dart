import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// macOS 本地通知桥接类，通过原生 MethodChannel 访问 UNUserNotificationCenter。
class MacNotificationBridge {
  MacNotificationBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('any_deck/notifications') {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  final MethodChannel _channel;
  final _clickStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// 通知点击事件流，包含 deviceId、targetTab、messageId 等 payload。
  Stream<Map<String, dynamic>> get clickStream => _clickStreamController.stream;

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onNotificationClicked') {
      final args = call.arguments;
      if (args is Map) {
        _clickStreamController.add(Map<String, dynamic>.from(args));
      }
    }
    return null;
  }

  /// 请求系统本地通知权限（alert, sound, badge）。
  Future<bool> requestAuthorization() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('requestAuthorization');
      return result ?? false;
    } catch (e) {
      debugPrint('[MacNotificationBridge] requestAuthorization error: $e');
      return false;
    }
  }

  /// 获取当前通知权限授权状态：'authorized' | 'denied' | 'notDetermined'。
  Future<String> getAuthorizationStatus() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return 'denied';
    }
    try {
      final status =
          await _channel.invokeMethod<String>('getAuthorizationStatus');
      return status ?? 'notDetermined';
    } catch (e) {
      debugPrint('[MacNotificationBridge] getAuthorizationStatus error: $e');
      return 'notDetermined';
    }
  }

  /// 发送一条系统本地通知。
  Future<bool> showNotification({
    required String id,
    required String title,
    String body = '',
    String subtitle = '',
    String? iconPath,
    Map<String, dynamic>? payload,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('showNotification', {
        'id': id,
        'title': title,
        'body': body,
        'subtitle': subtitle,
        if (iconPath != null && iconPath.isNotEmpty) 'iconPath': iconPath,
        'payload': payload ?? <String, dynamic>{},
      });
      return result ?? false;
    } catch (e) {
      debugPrint('[MacNotificationBridge] showNotification error: $e');
      return false;
    }
  }

  /// 移除指定标识符的已交付通知。
  Future<void> removeNotification(String id) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      await _channel.invokeMethod('removeNotification', {'id': id});
    } catch (e) {
      debugPrint('[MacNotificationBridge] removeNotification error: $e');
    }
  }

  /// 移除当前应用的所有已交付通知。
  Future<void> removeAllNotifications() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      await _channel.invokeMethod('removeAllNotifications');
    } catch (e) {
      debugPrint('[MacNotificationBridge] removeAllNotifications error: $e');
    }
  }

  /// 仅移除标识符使用指定前缀的已交付及待发送通知。
  Future<void> removeNotificationsWithPrefix(String prefix) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      await _channel.invokeMethod('removeNotificationsWithPrefix', {
        'prefix': prefix,
      });
    } catch (e) {
      debugPrint(
        '[MacNotificationBridge] removeNotificationsWithPrefix error: $e',
      );
    }
  }

  /// 打开 macOS 系统通知设置面板。
  Future<void> openNotificationSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      await _channel.invokeMethod('openNotificationSettings');
    } catch (e) {
      debugPrint('[MacNotificationBridge] openNotificationSettings error: $e');
    }
  }

  /// 向原生端通知 Flutter 已就绪，并取回启动期间缓存的点击事件。
  Future<List<Map<String, dynamic>>> ready() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return [];
    try {
      final clicks = await _channel.invokeListMethod<Map>('ready');
      if (clicks == null) return [];
      return clicks.map((c) => Map<String, dynamic>.from(c)).toList();
    } catch (e) {
      debugPrint('[MacNotificationBridge] ready error: $e');
      return [];
    }
  }

  void dispose() {
    _clickStreamController.close();
  }
}
