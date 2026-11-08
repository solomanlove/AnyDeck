import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../notifications/mac_notification_bridge.dart';
import 'harmony_share_service.dart';

/// 来件确认的唯一协调器：系统通知优先，弹窗兜底，共用一个确认期限。
/// 仅主窗口持有；通知动作必须匹配本次请求的随机 token 和通知 ID。
class HarmonyShareIncomingNotifications extends ChangeNotifier {
  HarmonyShareIncomingNotifications({
    required this.service,
    required this.bridge,
    required this.enabled,
    required this.text,
    this.deliveryFailed,
    this.operationTimeout = const Duration(seconds: 3),
    // 通知未被操作时尽早提供确认，避免长时间等待使手机转入 P2P 协商。
    this.fallbackDelay = const Duration(seconds: 2),
    this.offerTimeout = const Duration(seconds: 30),
  }) {
    unawaited(_clearOldNotifications());
    service.addListener(_serviceChanged);
    _serviceChanged();
  }

  final HarmonyShareService service;
  final MacNotificationBridge bridge;
  final bool Function() enabled;
  final String Function(String) text;
  final void Function(bool)? deliveryFailed;
  final Duration operationTimeout;
  final Duration fallbackDelay;
  final Duration offerTimeout;
  static const prefix = 'harmony_share_offer_';

  Future<bool>? _cleanup;
  final _random = Random.secure();
  ShareIncomingOffer? _offer;
  String? _token;
  String? _notificationId;
  Timer? _deadline;
  Timer? _fallback;
  bool _needsConfirmation = false;
  bool _settled = false;
  bool _disposed = false;

  ShareIncomingOffer? get offer => _offer;
  bool get needsConfirmation => _needsConfirmation;

  bool _current(ShareIncomingOffer offer) =>
      !_disposed &&
      !_settled &&
      identical(_offer, offer) &&
      identical(service.pendingOffer, offer);

  Future<bool> _clearOldNotifications() async {
    // 超时保留底层 Future：旧清理真正结束后，后续来件才能恢复通知。
    // 明确失败可在下一请求重试，不让一次暂时故障永久禁用通知。
    final cleanup = _cleanup ??=
        Future.sync(() => bridge.removeNotificationsWithPrefix(prefix)).then(
          (_) => true,
          onError: (Object _, StackTrace _) {
            _cleanup = null;
            return false;
          },
        );
    return cleanup.timeout(operationTimeout, onTimeout: () => false);
  }

  void _serviceChanged() {
    if (_disposed || identical(_offer, service.pendingOffer)) return;
    _clear();
    final offer = service.pendingOffer;
    _offer = offer;
    if (offer != null) {
      _settled = false;
      _token = List.generate(
        16,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final id = '$prefix$_token';
      _notificationId = id;
      _deadline = Timer(offerTimeout, () {
        if (!_current(offer)) return;
        _settled = true;
        service.expireOffer(offer);
      });
      _fallback = Timer(fallbackDelay, () => _showFallback(offer));
      if (!enabled()) {
        _needsConfirmation = true;
      } else {
        unawaited(_show(offer, id, _token!));
      }
    }
    notifyListeners();
  }

  Future<void> _show(ShareIncomingOffer offer, String id, String token) async {
    bool allowed() => _current(offer) && enabled();
    var deliveryExpired = false;
    try {
      final ready = await _clearOldNotifications();
      if (!allowed()) return;
      if (!ready) throw StateError('Notification cleanup unavailable');
      final status = await bridge.getAuthorizationStatus().timeout(
        operationTimeout,
      );
      if (!allowed()) return;
      if (status != 'authorized' && status != 'provisional') {
        if (status != 'denied' && status != 'notDetermined') {
          deliveryFailed?.call(true);
        }
        _showFallback(offer);
        return;
      }
      // 元数据仅用于应用内确认；系统通知不写设备名、文件名或目录。
      final delivery = bridge
          .showIncomingFileOffer(
            id: id,
            title: text('harmonyShareIncoming'),
            body: text('harmonyShareNotificationOffer'),
            acceptLabel: text('harmonyShareAccept'),
            rejectLabel: text('harmonyShareReject'),
            payload: {'type': 'harmony_share_offer', 'offerToken': token},
          )
          .then((sent) {
            if (deliveryExpired || !allowed()) unawaited(_remove(id));
            return sent;
          });
      final sent = await delivery.timeout(operationTimeout);
      if (!allowed()) return;
      deliveryFailed?.call(!sent);
      if (!sent) _showFallback(offer);
    } catch (_) {
      deliveryExpired = true;
      unawaited(_remove(id));
      if (!allowed()) return;
      deliveryFailed?.call(true);
      _showFallback(offer);
    }
  }

  void _showFallback(ShareIncomingOffer offer) {
    if (!_current(offer) || _needsConfirmation) return;
    _fallback?.cancel();
    _needsConfirmation = true;
    notifyListeners();
  }

  /// 旧通知、冷启动恢复和畸形动作均消费掉，不转交普通设备通知路由。
  bool handleClick(Map<String, dynamic> payload) {
    if (payload['type'] != 'harmony_share_offer') return false;
    final offer = _offer;
    if (offer == null ||
        !_current(offer) ||
        payload['offerToken'] != _token ||
        payload['notificationId'] != _notificationId) {
      return true;
    }
    switch (payload['notificationAction']) {
      case 'accept':
        decide(offer, true);
      case 'reject':
        decide(offer, false);
      case 'open':
      case 'dismiss':
        _showFallback(offer);
    }
    return true;
  }

  /// 弹窗和系统动作共用一次性决策入口，迟到的 Route 回调不能影响下一请求。
  void decide(ShareIncomingOffer offer, bool accept) {
    if (!_current(offer)) return;
    _settled = true;
    service.decide(accept);
  }

  void settingsChanged() {
    final offer = _offer;
    if (offer == null || enabled()) return;
    final id = _notificationId;
    if (id != null) unawaited(_remove(id));
    _showFallback(offer);
  }

  Future<void> _remove(String id) async {
    try {
      await bridge.removeNotification(id).timeout(operationTimeout);
    } catch (_) {
      // 撤回失败不能阻止请求失效；token 校验仍会拒绝过期点击。
    }
  }

  void _clear() {
    _deadline?.cancel();
    _fallback?.cancel();
    final id = _notificationId;
    _notificationId = null;
    _token = null;
    _needsConfirmation = false;
    if (id != null) unawaited(_remove(id));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    service.removeListener(_serviceChanged);
    _clear();
    super.dispose();
  }
}
