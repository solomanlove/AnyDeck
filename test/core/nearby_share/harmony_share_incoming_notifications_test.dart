import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/nearby_share/harmony_share_incoming_notifications.dart';
import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/harmony_share_notification_fakes.dart';

/// 将所有计时器放进 fakeAsync，验证真实期限而不等待或访问系统通知。
class _Harness {
  final service = ShareOfferTestService();
  final bridge = ShareNotificationTestBridge();
  final failures = <bool>[];
  bool enabled = true;
  late final incoming = HarmonyShareIncomingNotifications(
    service: service,
    bridge: bridge,
    enabled: () => enabled,
    text: (key) => 'zh:$key',
    deliveryFailed: failures.add,
  );

  ShareIncomingOffer offer({int bytes = 128}) {
    final offer = ShareIncomingOffer(InternetAddress('192.168.1.3'), bytes);
    service.offer(offer);
    return offer;
  }

  void dispose() {
    incoming.dispose();
    service.dispose();
  }
}

void _run(void Function(FakeAsync, _Harness) body) {
  fakeAsync((clock) {
    final h = _Harness();
    h.incoming;
    try {
      body(clock, h);
    } finally {
      h.dispose();
      clock.flushMicrotasks();
    }
  });
}

void main() {
  test('通知优先且同一来件只发送一次，接收前不修改服务决定', () {
    _run((clock, h) {
      final offer = h.offer();
      clock.flushMicrotasks();
      h.service.offer(offer);
      clock.flushMicrotasks();
      expect(h.bridge.shown, hasLength(1));
      expect(h.incoming.offer, same(offer));
      expect(h.incoming.needsConfirmation, isFalse);
      expect(h.service.decisions, isEmpty);
      expect(h.bridge.requests, 0);
      final shown = h.bridge.shown.single;
      expect(shown['acceptLabel'], 'zh:harmonyShareAccept');
      expect(shown['rejectLabel'], 'zh:harmonyShareReject');
      expect(shown.toString(), isNot(contains('192.168.1.3')));
      expect(shown['payload'], containsPair('type', 'harmony_share_offer'));
    });
  });

  for (final action in ['accept', 'reject']) {
    test('通知 $action 只处理一次，重复与相反动作均失效', () {
      _run((clock, h) {
        h.offer();
        clock.flushMicrotasks();
        final click = h.bridge.action(action);
        expect(h.incoming.handleClick(click), isTrue);
        h.incoming.handleClick(click);
        h.incoming.handleClick(
          h.bridge.action(action == 'accept' ? 'reject' : 'accept'),
        );
        clock.flushMicrotasks();
        expect(h.service.decisions, [action == 'accept']);
        expect(h.incoming.needsConfirmation, isFalse);
        expect(h.bridge.removed, contains(h.bridge.shown.single['id']));
        clock.elapse(const Duration(seconds: 31));
        expect(h.service.expired, isFalse);
      });
    });
  }

  test('通知优先且两秒未处理即兜底，总确认期限仍为三十秒', () {
    _run((clock, h) {
      final offer = h.offer();
      clock.flushMicrotasks();
      expect(h.bridge.shown, hasLength(1));
      clock.elapse(const Duration(milliseconds: 1999));
      expect(h.incoming.needsConfirmation, isFalse);
      clock.elapse(const Duration(milliseconds: 1));
      expect(h.incoming.needsConfirmation, isTrue);
      expect(h.service.decisions, isEmpty);
      clock.elapse(const Duration(seconds: 27));
      expect(h.service.expired, isFalse);
      clock.elapse(const Duration(seconds: 1));
      expect(h.service.expiredOffers, [offer]);
      expect(h.service.decisions, isEmpty);
      expect(h.incoming.needsConfirmation, isFalse);
      h.incoming.handleClick(h.bridge.action('accept'));
      expect(h.service.decisions, isEmpty);
    });
  });

  for (final action in ['open', 'dismiss']) {
    test('通知 $action 打开兜底且不自动接收或重置期限', () {
      _run((clock, h) {
        h.offer();
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 1));
        expect(h.incoming.needsConfirmation, isFalse);
        h.incoming.handleClick(h.bridge.action(action));
        expect(h.incoming.needsConfirmation, isTrue);
        expect(h.service.decisions, isEmpty);
        clock.elapse(const Duration(seconds: 29));
        expect(h.service.expired, isTrue);
      });
    });
  }

  for (final permission in ['denied', 'notDetermined', 'unknown']) {
    test('$permission 直接使用兜底，不在来件时请求系统权限', () {
      _run((clock, h) {
        h.bridge.permission = permission;
        h.offer();
        clock.flushMicrotasks();
        expect(h.incoming.needsConfirmation, isTrue);
        expect(h.bridge.shown, isEmpty);
        expect(h.bridge.requests, 0);
        expect(h.service.decisions, isEmpty);
      });
    });
  }

  test('关闭通知直接兜底，处理中关闭也撤回已发送通知', () {
    _run((clock, h) {
      h.enabled = false;
      h.offer();
      clock.flushMicrotasks();
      expect(h.incoming.needsConfirmation, isTrue);
      expect(h.bridge.shown, isEmpty);
      h.service.offer(null);
      h.enabled = true;
      h.offer(bytes: 256);
      clock.flushMicrotasks();
      expect(h.bridge.shown, hasLength(1));
      h.enabled = false;
      h.incoming.settingsChanged();
      clock.flushMicrotasks();
      expect(h.incoming.needsConfirmation, isTrue);
      expect(h.bridge.removed, contains(h.bridge.shown.single['id']));
    });
  });

  test('发送失败和桥接异常立即兜底，后续来件可恢复', () {
    _run((clock, h) {
      h.bridge.sent = false;
      h.offer();
      clock.flushMicrotasks();
      expect(h.incoming.needsConfirmation, isTrue);
      expect(h.failures.last, isTrue);
      h.service.offer(null);
      h.bridge.sent = true;
      h.bridge.throws = true;
      h.offer();
      clock.flushMicrotasks();
      expect(h.incoming.needsConfirmation, isTrue);
      expect(h.failures.last, isTrue);
      h.service.offer(null);
      h.bridge.throws = false;
      h.offer();
      clock.flushMicrotasks();
      expect(h.incoming.needsConfirmation, isFalse);
      expect(h.failures.last, isFalse);
    });
  });

  test('权限查询超时立即兜底，迟到授权不再发送本轮通知', () {
    _run((clock, h) {
      h.bridge.permissionGate = Completer();
      h.offer();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 3));
      expect(h.incoming.needsConfirmation, isTrue);
      expect(h.failures.last, isTrue);
      h.bridge.permissionGate!.complete('authorized');
      clock.flushMicrotasks();
      expect(h.bridge.shown, isEmpty);
    });
  });

  test('通知发送超时后迟到，仍撤回而不覆盖兜底', () {
    _run((clock, h) {
      h.bridge.deliveryGate = Completer();
      h.offer();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 3));
      expect(h.incoming.needsConfirmation, isTrue);
      expect(h.failures.last, isTrue);
      h.bridge.deliveryGate!.complete(true);
      clock.flushMicrotasks();
      expect(h.bridge.removed, contains(h.bridge.shown.single['id']));
      expect(h.incoming.needsConfirmation, isTrue);
      expect(h.service.decisions, isEmpty);
    });
  });

  test('启动清理超时先兜底，迟到完成后下一请求恢复通知', () {
    fakeAsync((clock) {
      final h = _Harness();
      h.bridge.cleanupGate = Completer();
      h.incoming;
      try {
        h.offer();
        clock.flushMicrotasks();
        expect(h.bridge.shown, isEmpty);
        clock.elapse(const Duration(seconds: 3));
        expect(h.incoming.needsConfirmation, isTrue);
        expect(h.failures.last, isTrue);
        h.offer(bytes: 256);
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 3));
        expect(h.incoming.needsConfirmation, isTrue);
        expect(h.bridge.prefixes, hasLength(1));
        expect(h.bridge.shown, isEmpty);
        h.bridge.cleanupGate!.complete();
        clock.flushMicrotasks();
        expect(h.bridge.shown, isEmpty);
        expect(h.service.decisions, isEmpty);
        final next = h.offer(bytes: 512);
        clock.flushMicrotasks();
        expect(h.bridge.shown, hasLength(1));
        expect(h.incoming.offer, same(next));
        expect(h.incoming.needsConfirmation, isFalse);
        expect(h.failures.last, isFalse);
        expect(h.bridge.prefixes, hasLength(1));
      } finally {
        h.dispose();
        clock.flushMicrotasks();
      }
    });
  });

  test('启动清理明确异常时本轮兜底，下轮重新清理并恢复通知', () {
    fakeAsync((clock) {
      final h = _Harness();
      h.bridge.cleanupGate = Completer();
      h.incoming;
      try {
        h.offer();
        clock.flushMicrotasks();
        h.bridge.cleanupGate!.completeError(StateError('cleanup failed'));
        clock.flushMicrotasks();
        expect(h.incoming.needsConfirmation, isTrue);
        expect(h.failures.last, isTrue);
        expect(h.bridge.shown, isEmpty);
        h.bridge.cleanupGate = null;
        final next = h.offer(bytes: 256);
        clock.flushMicrotasks();
        expect(h.bridge.prefixes, hasLength(2));
        expect(h.bridge.shown, hasLength(1));
        expect(h.incoming.offer, same(next));
        expect(h.incoming.needsConfirmation, isFalse);
        expect(h.failures.last, isFalse);
      } finally {
        h.dispose();
        clock.flushMicrotasks();
      }
    });
  });

  test('来件在启动清理期间已失效，清理完成不发送旧通知', () {
    fakeAsync((clock) {
      final h = _Harness();
      h.bridge.cleanupGate = Completer();
      h.incoming;
      try {
        h.offer();
        clock.flushMicrotasks();
        h.service.offer(null);
        h.bridge.cleanupGate!.complete();
        clock.flushMicrotasks();
        expect(h.bridge.shown, isEmpty);
        expect(h.incoming.needsConfirmation, isFalse);
      } finally {
        h.dispose();
        clock.flushMicrotasks();
      }
    });
  });

  test('旧通知或畸形动作不能处理新来件，两个标识都必须匹配', () {
    _run((clock, h) {
      final oldOffer = h.offer();
      clock.flushMicrotasks();
      final oldClick = h.bridge.action('accept');
      final next = h.offer(bytes: 256);
      clock.flushMicrotasks();
      final valid = h.bridge.action('accept', index: 1);
      for (final malformed in [
        oldClick,
        {...valid, 'notificationId': oldClick['notificationId']},
        {...valid, 'offerToken': oldClick['offerToken']},
        {...valid, 'offerToken': 123},
        {...valid, 'notificationAction': true},
        {...valid, 'notificationAction': 'unexpected'},
        {'type': 'harmony_share_offer', 'accept': true},
      ]) {
        expect(h.incoming.handleClick(malformed), isTrue);
      }
      h.incoming.decide(oldOffer, true);
      expect(h.service.decisions, isEmpty);
      expect(h.service.pendingOffer, same(next));
      expect(h.incoming.handleClick({'type': 'phone_message'}), isFalse);
      h.incoming.handleClick(valid);
      expect(h.service.decisions, [true]);
    });
  });

  test('旧权限查询完成不通知新来件，替换后旧期限不影响新请求', () {
    _run((clock, h) {
      final gate = Completer<String>();
      h.bridge.permissionGate = gate;
      h.offer();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      h.bridge.permissionGate = null;
      final next = h.offer(bytes: 256);
      clock.flushMicrotasks();
      gate.complete('authorized');
      clock.flushMicrotasks();
      expect(h.bridge.shown, hasLength(1));
      clock.elapse(const Duration(seconds: 29));
      expect(h.service.pendingOffer, same(next));
      expect(h.service.expired, isFalse);
      clock.elapse(const Duration(seconds: 1));
      expect(h.service.expiredOffers, [next]);
    });
  });

  test('弹窗决定和系统动作竞态只处理一次', () {
    _run((clock, h) {
      final offer = h.offer();
      clock.flushMicrotasks();
      h.incoming.handleClick(h.bridge.action('open'));
      h.incoming.decide(offer, false);
      h.incoming.handleClick(h.bridge.action('accept'));
      h.incoming.decide(offer, true);
      expect(h.service.decisions, [false]);
    });
  });

  test('销毁后忽略通知动作，迟到发送清理且不再触发计时器', () {
    fakeAsync((clock) {
      final h = _Harness();
      h.incoming;
      h.bridge.deliveryGate = Completer();
      h.offer();
      clock.flushMicrotasks();
      h.incoming.dispose();
      h.incoming.handleClick(h.bridge.action('accept'));
      h.bridge.deliveryGate!.complete(true);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 31));
      expect(h.bridge.removed, contains(h.bridge.shown.single['id']));
      expect(h.service.decisions, isEmpty);
      expect(h.service.expired, isFalse);
      h.service.dispose();
    });
  });
}
