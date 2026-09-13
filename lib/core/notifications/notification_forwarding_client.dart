import 'dart:convert';
import '../adb/adb_service.dart';
import 'notification_models.dart';

/// 负责通过 ADB shell 与 Companion ContentProvider 通信的底层客户端。
class NotificationForwardingClient {
  NotificationForwardingClient(this.adb);

  static const packageName = 'com.adbmanage.companion';
  final AdbService adb;

  static final RegExp _payloadPattern = RegExp(r'payload=([A-Za-z0-9+/=]+)');

  Future<int> getCurrentUser(String deviceId) async {
    final result = await adb.shellArgs(deviceId, ['am', 'get-current-user']);
    final user = int.tryParse(result.stdout.trim());
    if (!result.isSuccess || user == null || user < 0) {
      throw Exception('Failed to get current Android user');
    }
    return user;
  }

  Future<bool> isCompanionInstalled(String deviceId, int userId) async {
    final result = await adb.shellArgs(deviceId, [
      'pm',
      'path',
      '--user',
      '$userId',
      packageName,
    ]);
    return result.isSuccess && result.stdout.contains('package:');
  }

  Future<Map<String, dynamic>> _call(
    String deviceId,
    int userId,
    String method, [
    String? arg,
  ]) async {
    final args = <String>[
      'content',
      'call',
      '--user',
      '$userId',
      '--uri',
      'content://$packageName.usage',
      '--method',
      method,
    ];
    if (arg != null) {
      args.addAll(['--arg', arg]);
    }

    final result = await adb.shellArgs(
      deviceId,
      args,
      timeout: const Duration(seconds: 15),
    );
    if (!result.isSuccess) {
      throw Exception('ADB call failed: ${result.stderr}');
    }

    final match = _payloadPattern.firstMatch(result.stdout);
    if (match == null) {
      throw Exception('No payload in ADB response: ${result.stdout}');
    }

    final decoded = utf8.decode(base64Decode(match.group(1)!));
    return jsonDecode(decoded) as Map<String, dynamic>;
  }

  /// 获取手机端通知共享及监听权限状态。
  Future<NotificationSessionStatus> getStatus(
    String deviceId,
    int userId,
  ) async {
    final json = await _call(deviceId, userId, 'notification_status');
    return NotificationSessionStatus(
      isSharingEnabled: json['sharing'] as bool? ?? false,
      isPermissionGranted: json['permission'] as bool? ?? false,
      installationId: json['installationId'] as String? ?? '',
      androidUserId: (json['androidUserId'] as num?)?.toInt() ?? userId,
      rawStatus: json['status'] as String? ?? 'error',
    );
  }

  /// 开启增量转发会话。
  Future<String> startSession(String deviceId, int userId) async {
    final json = await _call(deviceId, userId, 'notification_start_session');
    final status = json['status'] as String?;
    if (status != 'ok') {
      throw Exception('Failed to start session: $status');
    }
    return json['sessionId'] as String;
  }

  /// 增量拉取事件。
  Future<Map<String, dynamic>> poll(
    String deviceId,
    int userId,
    String sessionId,
    int cursor,
  ) async {
    return _call(deviceId, userId, 'notification_poll', '$sessionId:$cursor');
  }

  /// 停止转发会话。
  Future<void> stopSession(
    String deviceId,
    int userId,
    String sessionId,
  ) async {
    try {
      await _call(deviceId, userId, 'notification_stop_session', sessionId);
    } catch (_) {
      // 容错处理
    }
  }
}
