import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/settings/app_settings.dart';
import '../adb/adb_device.dart';
import 'mac_notification_bridge.dart';
import 'notification_database.dart';
import 'notification_forwarding_client.dart';
import 'notification_models.dart';

/// 手机消息转发全局调度服务，管理各设备的增量轮询会话、并发限制与通知分发。
class NotificationForwardingService {
  NotificationForwardingService({
    required this.client,
    required this.databaseFuture,
    required this.bridge,
    required this.settingsGetter,
    required this.appNameResolver,
    required this.appIconPathResolver,
  });

  final NotificationForwardingClient client;
  final Future<NotificationDatabase> databaseFuture;
  final MacNotificationBridge bridge;
  final AppSettings Function() settingsGetter;
  final String? Function(String deviceId, String packageName) appNameResolver;
  final String? Function(String deviceId, String packageName) appIconPathResolver;

  // 全局并发最多 2 个
  int _activePolls = 0;
  static const int _maxConcurrentPolls = 2;

  final Map<String, _DeviceForwardingSession> _sessions = {};
  final _stateChangeController = StreamController<String>.broadcast();
  final _messageChangeController =
      StreamController<NotificationStoreChange>.broadcast();
  bool _isDisposed = false;

  Stream<String> get stateChanges => _stateChangeController.stream;

  Stream<NotificationStoreChange> get messageChanges =>
      _messageChangeController.stream;

  List<String> get activeSessionDeviceIds => _sessions.keys.toList();

  bool isForwardingActive(String deviceId) {
    return _sessions[deviceId]?.isRunning ?? false;
  }

  String? getSessionError(String deviceId) {
    return _sessions[deviceId]?.lastError;
  }

  bool isReconnecting(String deviceId) {
    return _sessions[deviceId]?.isReconnecting ?? false;
  }

  bool hasQueueGap(String deviceId) {
    return _sessions[deviceId]?.hasQueueGap ?? false;
  }

  /// 检查某物理设备是否已开启消息转发开关（保存在本地）。
  Future<bool> isForwardingEnabled(String serial) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('notifications.forwarding_enabled.$serial') ?? false;
  }

  /// 切换某物理设备的消息转发开关。
  Future<void> setForwardingEnabled(
    AdbDevice device,
    String serial,
    bool enabled,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications.forwarding_enabled.$serial', enabled);
    if (enabled) {
      final authorization = await bridge.getAuthorizationStatus();
      if (authorization == 'notDetermined') {
        await bridge.requestAuthorization();
      }
      startForwarding(device, serial);
    } else {
      stopForwarding(device.id);
    }
  }

  /// 获取设备已屏蔽的应用包名集合。
  Future<Set<String>> getBlockedApps(String serial) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('notifications.blocked_apps.$serial');
    return (list ?? []).toSet();
  }

  /// 设置应用屏蔽或解除屏蔽。
  Future<void> toggleBlockApp(
    String serial,
    String packageName,
    bool block,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getBlockedApps(serial);
    if (block) {
      current.add(packageName);
    } else {
      current.remove(packageName);
    }
    await prefs.setStringList(
      'notifications.blocked_apps.$serial',
      current.toList(),
    );
  }

  /// 启动某台设备的转发会话。
  void startForwarding(AdbDevice device, String serial) {
    if (_isDisposed) return;
    if (_sessions.containsKey(device.id)) {
      _sessions[device.id]?.stop();
    }
    final session = _DeviceForwardingSession(
      device: device,
      serial: serial,
      service: this,
    );
    _sessions[device.id] = session;
    session.start();
  }

  /// 停止某台设备的转发会话。
  void stopForwarding(String deviceId) {
    final session = _sessions.remove(deviceId);
    session?.stop();
    _emitStateChange(deviceId);
  }

  /// 释放所有资源。
  void dispose() {
    _isDisposed = true;
    for (final session in _sessions.values) {
      session.stop();
    }
    _sessions.clear();
    _stateChangeController.close();
    _messageChangeController.close();
  }

  Future<void> _acquirePollSlot() async {
    while (!_isDisposed && _activePolls >= _maxConcurrentPolls) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (_isDisposed) return;
    _activePolls++;
  }

  void _releasePollSlot() {
    if (_activePolls > 0) _activePolls--;
  }

  void _emitStateChange(String deviceId) {
    if (!_isDisposed && !_stateChangeController.isClosed) {
      _stateChangeController.add(deviceId);
    }
  }

  void _emitMessageChange(String deviceId, String installationId, int userId) {
    if (!_isDisposed && !_messageChangeController.isClosed) {
      _messageChangeController.add(
        NotificationStoreChange(
          installationId: installationId,
          androidUserId: userId,
          deviceId: deviceId,
        ),
      );
    }
  }
}

class _DeviceForwardingSession {
  _DeviceForwardingSession({
    required this.device,
    required this.serial,
    required this.service,
  });

  final AdbDevice device;
  final String serial;
  final NotificationForwardingService service;

  Timer? _timer;
  bool _isDisposed = false;
  bool _isPolling = false;
  bool isReconnecting = false;
  bool hasQueueGap = false;
  String? lastError;
  String? _sessionId;
  int _currentUser = 0;
  int _cursor = 0;
  String _installationId = '';
  int _backoffSeconds = 2;

  bool get isRunning => !_isDisposed && lastError == null;

  void start() {
    _timer = Timer(Duration.zero, _pollTick);
  }

  void stop() {
    _isDisposed = true;
    _timer?.cancel();
    final sid = _sessionId;
    if (sid != null) {
      service.client.stopSession(device.id, _currentUser, sid);
    }
  }

  Future<void> _pollTick() async {
    if (_isDisposed || _isPolling) return;
    _isPolling = true;

    try {
      await service._acquirePollSlot();
      if (_isDisposed || service._isDisposed) return;

      // 1. 握手与会话建立
      if (_sessionId == null) {
        _currentUser = await service.client.getCurrentUser(device.id);
        final status = await service.client.getStatus(device.id, _currentUser);
        if (!status.isReady) {
          lastError = status.rawStatus;
          service._emitStateChange(device.id);
          _scheduleNext(const Duration(seconds: 4));
          return;
        }
        _installationId = status.installationId;
        final database = await service.databaseFuture;
        await database.linkSource(
          [serial, device.id],
          _installationId,
          _currentUser,
        );
        _sessionId = await service.client.startSession(device.id, _currentUser);
        _cursor = 0;
        isReconnecting = false;
        lastError = null;
        _backoffSeconds = 2;
        service._emitStateChange(device.id);
      }

      // 2. 轮询增量事件
      final result = await service.client.poll(
        device.id,
        _currentUser,
        _sessionId!,
        _cursor,
      );
      final status = result['status'] as String?;
      if (status == 'session_expired') {
        // 会话失效，标记重新连接并重新初始化
        _sessionId = null;
        isReconnecting = true;
        service._emitStateChange(device.id);
        _scheduleNext(const Duration(seconds: 1));
        return;
      } else if (status != 'ok') {
        throw Exception('Poll status error: $status');
      }

      final nextCursor = (result['nextCursor'] as num?)?.toInt() ?? _cursor;
      if (result['gap'] == true) {
        hasQueueGap = true;
        service._emitStateChange(device.id);
      }
      final rawEvents = result['events'] as List<dynamic>? ?? [];
      final blockedApps = await service.getBlockedApps(serial);
      final database = await service.databaseFuture;

      for (final raw in rawEvents) {
        if (raw is! Map<String, dynamic>) continue;
        final event = NotificationEvent.fromJson(raw);

        if (event.event == 'removed') {
          await database.markAsRemoved(
            _installationId,
            _currentUser,
            event.key,
          );
          await service.bridge.removeNotification(_notificationId(event.key));
          service._emitMessageChange(device.id, _installationId, _currentUser);
        } else if (event.event == 'posted') {
          if (blockedApps.contains(event.packageName)) {
            // 被屏蔽的应用跳过入库与通知
            continue;
          }

          final appName = service.appNameResolver(
            device.id,
            event.packageName,
          );
          final msg = NotificationMessage(
            installationId: _installationId,
            androidUserId: _currentUser,
            notificationKey: event.key,
            packageName: event.packageName,
            appName: appName,
            title: event.title,
            content: event.content,
            postTime: event.postTime,
            receivedTime: DateTime.now(),
          );

          final saved = await database.insertOrUpdate(msg);

          // 发送 macOS 本地通知
          final settings = service.settingsGetter();
          final previewBody = settings.notificationBodyPreview;
          final notifTitle = (appName != null && appName.isNotEmpty)
              ? '$appName: ${event.title}'
              : (event.title.isNotEmpty ? event.title : event.packageName);
          final notifBody = previewBody ? event.content : '';

          await service.bridge.showNotification(
            id: _notificationId(event.key),
            title: notifTitle,
            body: notifBody,
            iconPath: service.appIconPathResolver(device.id, event.packageName),
            payload: {
              'type': 'phone_message',
              'deviceId': device.id,
              'deviceSerial': serial,
              'targetTab': 15,
              'messageId': saved.id,
              'notificationKey': event.key,
            },
          );
          service._emitMessageChange(device.id, _installationId, _currentUser);
        }
      }

      _cursor = nextCursor;

      _backoffSeconds = 2;
      lastError = null;
      isReconnecting = false;
      _scheduleNext(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('[NotificationSession] error for ${device.id}: $e');
      lastError = e.toString();
      _sessionId = null;
      isReconnecting = true;
      service._emitStateChange(device.id);

      // 退避重试：2s, 4s, 8s, max 16s
      _scheduleNext(Duration(seconds: _backoffSeconds));
      _backoffSeconds = (_backoffSeconds * 2).clamp(2, 16);
    } finally {
      service._releasePollSlot();
      _isPolling = false;
    }
  }

  void _scheduleNext(Duration delay) {
    if (_isDisposed) return;
    _timer?.cancel();
    _timer = Timer(delay, _pollTick);
  }

  String _notificationId(String notificationKey) =>
      'notif_${_installationId}_${_currentUser}_$notificationKey';
}
