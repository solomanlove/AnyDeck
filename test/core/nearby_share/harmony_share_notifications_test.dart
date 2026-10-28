import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/nearby_share/harmony_share_notifications.dart';
import 'package:any_deck/core/nearby_share/harmony_share_send_queue.dart';
import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_history_database.dart';
import 'package:any_deck/core/nearby_share/share_network.dart';
import 'package:any_deck/core/nearby_share/share_send_selection.dart';
import 'package:any_deck/core/nearby_share/share_transfer_history.dart';
import 'package:any_deck/core/nearby_share/share_transfer_record.dart';
import 'package:any_deck/core/notifications/mac_notification_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

class _Database extends Fake implements ShareHistoryDatabase {
  @override
  Future<void> recoverInterrupted() async {}
  @override
  Future<List<ShareTransferRecord>> query({
    ShareTransferDirection? direction,
    String search = '',
    ShareTransferRecord? before,
    int limit = 100,
  }) async => [
    ShareTransferRecord(
      id: 'old-success',
      direction: ShareTransferDirection.receive,
      status: ShareTransferStatus.succeeded,
      deviceName: 'old',
      address: '1.2.3.4',
      fileName: 'old.bin',
      bytes: 10,
      createdAt: DateTime(2026),
    ),
  ];
  @override
  Future<void> save(List<ShareTransferRecord> records) async {}
}

class _Client extends Fake implements ShareCoreClient {}

class _Service extends HarmonyShareService {
  _Service(ShareTransferHistory history)
    : super.testing(
        client: _Client(),
        history: history,
        detectNetwork: () async => ShareNetwork(
          InternetAddress.loopbackIPv4,
          InternetAddress('127.255.255.255'),
        ),
        downloads: () async => null,
      );
  void offer(ShareIncomingOffer? offer) {
    pendingOffer = offer;
    notifyListeners();
  }
}

class _Bridge extends Fake implements MacNotificationBridge {
  final shown = <Map<String, dynamic>>[];
  final removed = <String>[];
  final prefixes = <String>[];
  String permission = 'authorized';
  bool sent = true;
  bool throws = false;
  int requests = 0;
  Completer<String>? permissionGate;
  Completer<bool>? deliveryGate;
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
  Future<void> removeNotification(String id) async {
    removed.add(id);
  }

  @override
  Future<void> removeNotificationsWithPrefix(String prefix) async {
    prefixes.add(prefix);
  }
}

Future<void> _turns() async {
  for (var n = 0; n < 12; n++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late ShareTransferHistory history;
  late _Service service;
  late _Bridge bridge;
  late HarmonyShareSendQueue queue;
  late HarmonyShareNotifications notifications;
  var enabled = true;
  var language = 'zh';
  setUp(() {
    history = ShareTransferHistory(open: () async => _Database());
    service = _Service(history);
    bridge = _Bridge();
    queue = HarmonyShareSendQueue(
      send: (item, _) async {
        if (item.file.name == 'fail') throw StateError('synthetic failure');
      },
      cancelActive: () {},
    );
    enabled = true;
    language = 'zh';
    notifications = HarmonyShareNotifications(
      service: service,
      queue: queue,
      bridge: bridge,
      enabled: () => enabled,
      text: (key) => '$language:$key',
    );
  });
  tearDown(() async {
    notifications.dispose();
    await history.flush();
    service.dispose();
    history.dispose();
    queue.dispose();
  });

  test('来件只通知一次且处理后移除，不包含路径或自动接收动作', () async {
    final offer = ShareIncomingOffer(InternetAddress('192.168.1.3'), 100);
    service.offer(offer);
    await _turns();
    service.offer(offer);
    await _turns();
    expect(bridge.shown, hasLength(1));
    expect(bridge.shown.single['payload'], {
      'type': 'harmony_share',
      'targetTab': -4,
    });
    expect(service.pendingOffer, same(offer));
    service.offer(null);
    await _turns();
    expect(bridge.removed, contains(bridge.shown.single['id']));
    expect(bridge.prefixes, contains('harmony_share_offer_'));
  });

  test('权限查询期间来件失效不发送过期通知', () async {
    bridge.permissionGate = Completer();
    service.offer(ShareIncomingOffer(InternetAddress.loopbackIPv4, 100));
    await _turns();
    service.offer(null);
    bridge.permissionGate!.complete('authorized');
    await _turns();
    expect(bridge.shown, isEmpty);
  });

  test('送达期间来件失效仍撤回，关闭功能也清理自己的通知', () async {
    bridge.deliveryGate = Completer();
    service.offer(ShareIncomingOffer(InternetAddress.loopbackIPv4, 100));
    await _turns();
    service.offer(null);
    enabled = false;
    notifications.settingsChanged();
    bridge.deliveryGate!.complete(true);
    await _turns();
    expect(bridge.removed, contains(bridge.shown.single['id']));
    expect(bridge.prefixes, contains(HarmonyShareNotifications.prefix));
  });

  for (final permission in ['denied', 'notDetermined', 'unknown']) {
    test('后台不请求权限：$permission', () async {
      bridge.permission = permission;
      service.offer(ShareIncomingOffer(InternetAddress.loopbackIPv4, 100));
      await _turns();
      expect(bridge.shown, isEmpty);
      expect(bridge.requests, 0);
    });
  }

  test('接收终态去重，成功与失败摘要按当前语言发送', () async {
    final id = history.incoming(
      address: '192.168.1.3',
      name: 'private peer',
      bytes: 100,
    );
    history.receiveChanged(
      id,
      status: ShareTransferStatus.succeeded,
      fileName: 'private.txt',
      path: '/private/path',
    );
    history.receiveChanged(id, status: ShareTransferStatus.succeeded);
    await _turns();
    expect(bridge.shown, hasLength(1));
    expect(bridge.shown.single['title'], 'zh:harmonyShareNotificationReceived');
    expect(bridge.shown.single.toString(), isNot(contains('private')));
    language = 'en';
    final failed = history.incoming(
      address: '1.2.3.4',
      name: 'peer',
      bytes: 100,
    );
    history.receiveChanged(failed, status: ShareTransferStatus.failed);
    await _turns();
    expect(
      bridge.shown.last['title'],
      'en:harmonyShareNotificationReceiveFailed',
    );
  });

  test('旧记录加载不重放通知，主动拒绝/取消也不生成完成提醒', () async {
    await history.initialize();
    expect(history.recent.any((record) => record.id == 'old-success'), isTrue);
    for (final status in [
      ShareTransferStatus.rejected,
      ShareTransferStatus.cancelled,
    ]) {
      final id = history.incoming(address: '1.2.3.4', name: 'peer', bytes: 100);
      history.receiveChanged(id, status: status);
    }
    await _turns();
    expect(bridge.shown, isEmpty);
  });

  test('原生 100 文件批次完成只通知一次，进度不提前发成功', () async {
    final waiting = Completer<void>();
    late void Function(ShareCoreProgress) progress;
    final native = HarmonyShareSendQueue(
      send: (_, _) => throw StateError('legacy not expected'),
      sendBatch: (_, callback) {
        progress = callback;
        return waiting.future;
      },
      cancelActive: () {},
    );
    final coordinator = HarmonyShareNotifications(
      service: service,
      queue: native,
      bridge: bridge,
      enabled: () => true,
      text: (key) => key == 'harmonyShareNotificationBatchSummary'
          ? '{success}/{failed}/{cancelled}'
          : key,
    );
    try {
      final run = native.run(
        ShareCorePeer(
          address: InternetAddress.loopbackIPv4,
          port: 1234,
          name: 'peer',
        ),
        ShareSendSelection([
          for (var index = 0; index < 100; index++)
            ShareSendFile(
              file: File('/synthetic/$index.bin'),
              bytes: 1,
              modified: DateTime(2026),
            ),
        ]),
      );
      await _turns();
      progress(
        const ShareCoreProgress(direction: 'send', bytes: 100, totalBytes: 100),
      );
      await _turns();
      expect(bridge.shown, isEmpty);
      waiting.complete();
      await run;
      await _turns();
      expect(bridge.shown, hasLength(1));
      expect(bridge.shown.single['body'], '100/0/0');
    } finally {
      coordinator.dispose();
      native.dispose();
    }
  });

  test('发送多文件只汇总整批一次，并保留三种结果计数', () async {
    final waiting = Completer<void>();
    final mixed = HarmonyShareSendQueue(
      send: (item, _) async {
        if (item.file.name == 'wait') await waiting.future;
        if (item.file.name == 'fail') throw StateError('failure');
      },
      cancelActive: () {},
    );
    notifications.dispose();
    notifications = HarmonyShareNotifications(
      service: service,
      queue: mixed,
      bridge: bridge,
      enabled: () => true,
      text: (key) => key == 'harmonyShareNotificationBatchSummary'
          ? '{success}/{failed}/{cancelled}'
          : key,
    );
    final run = mixed.run(
      ShareCorePeer(
        address: InternetAddress.loopbackIPv4,
        port: 1234,
        name: 'peer',
      ),
      ShareSendSelection([
        for (final name in ['wait', 'fail', 'cancel'])
          ShareSendFile(
            file: File('/synthetic/$name'),
            bytes: 1,
            modified: DateTime(2026),
          ),
      ]),
    );
    mixed.cancel(mixed.items.last.id);
    waiting.complete();
    await run;
    await _turns();
    expect(bridge.shown, hasLength(1));
    expect(bridge.shown.single['body'], '1/1/1');
    notifications.dispose();
    mixed.dispose();
    notifications = HarmonyShareNotifications(
      service: service,
      queue: queue,
      bridge: bridge,
      enabled: () => true,
      text: (key) => key,
    );
  });

  test('桥接异常不影响来件状态，后续通知可恢复', () async {
    bridge.throws = true;
    service.offer(ShareIncomingOffer(InternetAddress.loopbackIPv4, 100));
    await _turns();
    expect(notifications.deliveryFailed.value, isTrue);
    expect(service.pendingOffer, isNotNull);
    bridge.throws = false;
    service.offer(null);
    service.offer(ShareIncomingOffer(InternetAddress.loopbackIPv4, 101));
    await _turns();
    expect(bridge.shown, hasLength(1));
    expect(notifications.deliveryFailed.value, isFalse);
  });

  test('权限查询期间停用或销毁不再发送，拒绝送达可被用户发现', () async {
    bridge.sent = false;
    service.offer(ShareIncomingOffer(InternetAddress.loopbackIPv4, 100));
    await _turns();
    expect(notifications.deliveryFailed.value, isTrue);
    service.offer(null);
    bridge.permissionGate = Completer();
    service.offer(ShareIncomingOffer(InternetAddress.loopbackIPv4, 101));
    await _turns();
    enabled = false;
    notifications.settingsChanged();
    bridge.permissionGate!.complete('authorized');
    await _turns();
    expect(bridge.shown, hasLength(1));
    enabled = true;
    bridge.permissionGate = Completer();
    service.offer(ShareIncomingOffer(InternetAddress.loopbackIPv4, 102));
    await _turns();
    notifications.dispose();
    bridge.permissionGate!.complete('authorized');
    await _turns();
    expect(bridge.shown, hasLength(1));
    notifications = HarmonyShareNotifications(
      service: service,
      queue: queue,
      bridge: bridge,
      enabled: () => false,
      text: (key) => key,
    );
  });

  test('原生通知送达超时后迟到，仍清理已经失效的来件', () async {
    notifications.dispose();
    notifications = HarmonyShareNotifications(
      service: service,
      queue: queue,
      bridge: bridge,
      enabled: () => enabled,
      text: (key) => key,
      operationTimeout: const Duration(milliseconds: 20),
    );
    bridge.deliveryGate = Completer();
    service.offer(ShareIncomingOffer(InternetAddress.loopbackIPv4, 100));
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!notifications.deliveryFailed.value) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('No notification timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(bridge.shown, hasLength(1));
    service.offer(null);
    bridge.deliveryGate!.complete(true);
    await _turns();
    expect(bridge.removed, contains(bridge.shown.single['id']));
  });

  test('通知点击只导航互联页，忽略其他动作与畸形设备字段', () {
    var opened = 0;
    expect(
      routeHarmonyShareNotification({
        'type': 'harmony_share',
        'deviceId': 42,
        'path': '/private/path',
        'accept': true,
      }, () => opened++),
      isTrue,
    );
    expect(opened, 1);
    expect(service.pendingOffer, isNull);
    expect(
      routeHarmonyShareNotification({'type': 'phone_message'}, () => opened++),
      isFalse,
    );
    expect(opened, 1);
  });
  test('百文件接收只生成一条批次通知，不按子记录刷屏', () async {
    final id = history.incoming(
      address: '1.2.3.4',
      name: 'peer',
      bytes: 100,
      fileCount: 100,
    );
    history.receivedBatch(id, [
      for (var i = 0; i < 100; i++)
        {'path': '/synthetic/$i.bin', 'bytes': 1, 'sha256': 'a' * 64},
    ], '/synthetic');
    await _turns();
    expect(bridge.shown, hasLength(1));
    expect(
      bridge.shown.single['title'],
      'zh:harmonyShareNotificationBatchReceived',
    );
  });
}
