import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../notifications/mac_notification_bridge.dart';
import 'harmony_share_incoming_notifications.dart';
import 'harmony_share_send_queue.dart';
import 'harmony_share_service.dart';
import 'share_transfer_record.dart';

/// 主窗口通知协调器；复用既有桥接，不申请权限、不打开文件或自动接受来件。
/// text 在发送时解析当前语言；enabled 在每次异步边界后复核。
class HarmonyShareNotifications {
  HarmonyShareNotifications({
    required this.service,
    required this.queue,
    required this.bridge,
    required this.enabled,
    required this.text,
    this.operationTimeout = const Duration(seconds: 5),
  }) {
    incoming = HarmonyShareIncomingNotifications(
      service: service,
      bridge: bridge,
      enabled: enabled,
      text: text,
      operationTimeout: operationTimeout,
      deliveryFailed: (failed) {
        if (!_disposed) deliveryFailed.value = failed;
      },
    );
    queue.addListener(_queueChanged);
    service.outbox.addListener(_outboxChanged);
    _history = service.history?.changes.listen(_recordChanged);
    _queueRunning = queue.running;
    _outboxRunning = service.outbox.running;
  }

  final HarmonyShareService service;
  final HarmonyShareSendQueue queue;
  final MacNotificationBridge bridge;
  final bool Function() enabled;
  final String Function(String) text;
  final deliveryFailed = ValueNotifier(false);
  final _tasks = Queue<Future<void> Function()>();
  final _results = <String, ShareTransferStatus>{};
  StreamSubscription<ShareTransferRecord>? _history;
  late final HarmonyShareIncomingNotifications incoming;
  bool _queueRunning = false;
  bool _outboxRunning = false;
  bool _working = false;
  bool _disposed = false;
  static const prefix = 'harmony_share_';
  final Duration operationTimeout;

  void _recordChanged(ShareTransferRecord record) {
    if (record.batchId != null || record.direction != ShareTransferDirection.receive ||
        !record.terminal) {
      return;
    }
    if (_results[record.id] == record.status) return;
    _results[record.id] = record.status;
    if (_results.length > 256) _results.remove(_results.keys.first);
    final key = switch (record.status) {
      ShareTransferStatus.succeeded => record.fileCount > 1 ? 'harmonyShareNotificationBatchReceived' : 'harmonyShareNotificationReceived',
      ShareTransferStatus.failed ||
      ShareTransferStatus.interrupted ||
      ShareTransferStatus.timedOut => 'harmonyShareNotificationReceiveFailed',
      _ => null,
    };
    if (key == null) return;
    _enqueue(
      () => _show(
        id: '${prefix}record_${record.id}',
        title: text(key).replaceAll('{count}', '${record.fileCount}'),
        body: text('harmonyShareNotificationResultHint'),
        valid: () => _results[record.id] == record.status,
      ),
    );
  }

  void _queueChanged() {
    final completed = _queueRunning && !queue.running;
    _queueRunning = queue.running;
    if (!completed || queue.items.isEmpty || service.outbox.running) return;
    final id = '${prefix}batch_${queue.items.first.id}';
    final success = queue.count(ShareSendStatus.succeeded);
    final failed = queue.count(ShareSendStatus.failed);
    final cancelled = queue.count(ShareSendStatus.cancelled);
    _enqueue(
      () => _show(
        id: id,
        title: text('harmonyShareNotificationBatch'),
        body: text('harmonyShareNotificationBatchSummary')
            .replaceAll('{success}', '$success')
            .replaceAll('{failed}', '$failed')
            .replaceAll('{cancelled}', '$cancelled'),
      ),
    );
  }

  /// 原生连续队列按整个调度周期通知一次；单批兼容队列仍走原回调。
  void _outboxChanged() {
    final outbox = service.outbox;
    final completed = _outboxRunning && !outbox.running;
    _outboxRunning = outbox.running;
    if (!completed) return;
    final success = outbox.succeeded;
    final failed = outbox.failed;
    final cancelled = outbox.cancelled;
    final id = '${prefix}outbox_${outbox.cycleId}';
    _enqueue(
      () => _show(
        id: id,
        title: text('harmonyShareNotificationOutbox'),
        body: text('harmonyShareNotificationBatchSummary')
            .replaceAll('{success}', '$success')
            .replaceAll('{failed}', '$failed')
            .replaceAll('{cancelled}', '$cancelled'),
      ),
    );
  }

  Future<void> _show({
    required String id,
    required String title,
    required String body,
    bool Function()? valid,
  }) async {
    bool allowed() => !_disposed && enabled() && (valid?.call() ?? true);
    if (!allowed()) return;
    try {
      final status = await bridge.getAuthorizationStatus().timeout(
        operationTimeout,
      );
      if (!allowed()) return;
      if (status != 'authorized' && status != 'provisional') {
        // 无法查询权限不同于用户拒绝/尚未申请；提示失败，等待后续通知恢复。
        if (status != 'denied' && status != 'notDetermined') {
          deliveryFailed.value = true;
        }
        return;
      }
      // 通知仅包含通用摘要，设备名、文件名和本地路径留在应用内。
      final delivery = bridge
          .showNotification(
            id: id,
            title: title,
            body: body,
            payload: const {'type': 'harmony_share', 'targetTab': -4},
          )
          .then((sent) async {
            // 保留迟到完成回调；外层超时后到达的原生送达也要撤回失效来件。
            if (!allowed()) {
              await bridge.removeNotification(id).timeout(operationTimeout);
            }
            return sent;
          });
      final sent = await delivery.timeout(operationTimeout);
      if (allowed()) deliveryFailed.value = !sent;
    } catch (_) {
      // 失效来件或停用期间的迟到异常不应覆盖当前通知健康状态。
      if (allowed()) rethrow;
    }
  }

  /// 有界串行通知队列；系统 API 挂起不会阻断收发或无限积压。
  void _enqueue(Future<void> Function() task) {
    if (_disposed) return;
    if (_tasks.length >= 16) _tasks.removeFirst();
    _tasks.add(task);
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_working) return;
    _working = true;
    try {
      while (!_disposed && _tasks.isNotEmpty) {
        try {
          await _tasks.removeFirst()().timeout(operationTimeout * 3);
        } catch (_) {
          if (!_disposed && enabled()) deliveryFailed.value = true;
        }
      }
    } finally {
      _working = false;
    }
  }

  void settingsChanged() {
    incoming.settingsChanged();
    if (!enabled()) {
      _enqueue(() => bridge.removeNotificationsWithPrefix(prefix));
    }
  }

  void dispose() {
    _disposed = true;
    incoming.dispose();
    queue.removeListener(_queueChanged);
    service.outbox.removeListener(_outboxChanged);
    unawaited(_history?.cancel());
    _tasks.clear();
    deliveryFailed.dispose();
  }
}

/// 在通用设备通知解析前识别互传通知；payload 不携带可执行动作或路径。
bool routeHarmonyShareNotification(
  Map<String, dynamic> payload,
  VoidCallback open,
) {
  if (payload['type'] != 'harmony_share') return false;
  open();
  return true;
}
