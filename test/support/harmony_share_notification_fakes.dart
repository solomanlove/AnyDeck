import 'dart:async';

import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/notifications/mac_notification_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 来件测试服务：记录人工决定和超时，避免启动真实 Core 或写入用户文件。
class ShareOfferTestService extends ChangeNotifier
    implements HarmonyShareService {
  @override
  ShareIncomingOffer? pendingOffer;
  @override
  final Map<String, ShareCorePeer> peers = {};
  final decisions = <bool>[];
  final expiredOffers = <ShareIncomingOffer>[];
  bool get expired => expiredOffers.isNotEmpty;

  void offer(ShareIncomingOffer? value) {
    pendingOffer = value;
    notifyListeners();
  }

  @override
  void decide(bool accept) {
    decisions.add(accept);
    offer(null);
  }

  @override
  void expireOffer(ShareIncomingOffer offer) {
    if (!identical(offer, pendingOffer)) return;
    expiredOffers.add(offer);
    this.offer(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 可控制原生异步完成时机的通知桥接，所有内容仅保存在内存中。
class ShareNotificationTestBridge extends Fake
    implements MacNotificationBridge {
  final shown = <Map<String, dynamic>>[];
  final removed = <String>[];
  final prefixes = <String>[];
  String permission = 'authorized';
  bool sent = true;
  bool throws = false;
  int requests = 0;
  Completer<String>? permissionGate;
  Completer<bool>? deliveryGate;
  Completer<void>? cleanupGate;

  @override
  Future<String> getAuthorizationStatus() async {
    if (throws) throw StateError('notification bridge failed');
    return permissionGate?.future ?? permission;
  }

  @override
  Future<bool> requestAuthorization() async {
    requests++;
    return false;
  }

  @override
  Future<bool> showNotification({
    required String id,
    required String title,
    String body = '',
    String subtitle = '',
    String? iconPath,
    Map<String, dynamic>? payload,
  }) async {
    shown.add({'id': id, 'title': title, 'body': body, 'payload': payload});
    return deliveryGate?.future ?? sent;
  }

  @override
  Future<bool> showIncomingFileOffer({
    required String id,
    required String title,
    required String body,
    required String acceptLabel,
    required String rejectLabel,
    required Map<String, dynamic> payload,
  }) async {
    shown.add({
      'id': id,
      'title': title,
      'body': body,
      'acceptLabel': acceptLabel,
      'rejectLabel': rejectLabel,
      'payload': payload,
    });
    return deliveryGate?.future ?? sent;
  }

  Map<String, dynamic> action(String action, {int index = 0}) => {
    ...shown[index]['payload'] as Map<String, dynamic>,
    'notificationId': shown[index]['id'],
    'notificationAction': action,
  };

  @override
  Future<void> removeNotification(String id) async {
    removed.add(id);
  }

  @override
  Future<void> removeNotificationsWithPrefix(String prefix) async {
    prefixes.add(prefix);
    await cleanupGate?.future;
  }
}
