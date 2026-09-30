import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/notifications/notification_models.dart';
import '../../../../core/notifications/notification_providers.dart';

class _TargetMessageIdNotifier extends Notifier<int?> {
  @override
  int? build() => null;
  @override
  set state(int? value) => super.state = value;
}

/// 系统通知点击跳转时需高亮定位的目标消息 ID。
final targetMessageIdProvider =
    NotifierProvider<_TargetMessageIdNotifier, int?>(
      _TargetMessageIdNotifier.new,
    );

class _HighlightedNotificationKeyNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  @override
  set state(String? value) => super.state = value;
}

/// 系统通知点击跳转时需高亮定位的目标通知 Key。
final highlightedNotificationKeyProvider =
    NotifierProvider<_HighlightedNotificationKeyNotifier, String?>(
      _HighlightedNotificationKeyNotifier.new,
    );

class _MessagesSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  @override
  set state(String value) => super.state = value;
}

/// 消息关键词搜索 Provider。
final messagesSearchQueryProvider =
    NotifierProvider<_MessagesSearchQueryNotifier, String>(
      _MessagesSearchQueryNotifier.new,
    );

class _MessagesPackageFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  @override
  set state(String? value) => super.state = value;
}

/// 消息包名筛选 Provider。
final messagesPackageFilterProvider =
    NotifierProvider<_MessagesPackageFilterNotifier, String?>(
      _MessagesPackageFilterNotifier.new,
    );

/// 当前设备的已屏蔽应用集合 Provider。
final blockedAppsProvider =
    FutureProvider.autoDispose.family<Set<String>, String>((ref, serial) async {
      final service = ref.watch(notificationForwardingServiceProvider);
      return service.getBlockedApps(serial);
    });

/// 当前设备的消息转发开关状态 Provider。
final forwardingEnabledProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, serial) async {
      final service = ref.watch(notificationForwardingServiceProvider);
      return service.isForwardingEnabled(serial);
    });

/// 根据物理 serial 或历史 route 恢复最近一次 Companion 安装实例。
final notificationSourceProvider = FutureProvider.autoDispose
    .family<NotificationSource?, String>((ref, alias) async {
      final db = await ref.watch(notificationDatabaseProvider.future);
      return db.resolveSource(alias);
    });

/// 点击目标保留原始来源，不能仅依赖当前设备最近一次安装映射。
typedef MessageClickTarget = ({
  String deviceId,
  String? serial,
  String installationId,
  int userId,
});

class _MessageClickTargetNotifier extends Notifier<MessageClickTarget?> {
  @override
  MessageClickTarget? build() => null;
  @override
  set state(MessageClickTarget? value) => super.state = value;
}

final messageClickTargetProvider =
    NotifierProvider<_MessageClickTargetNotifier, MessageClickTarget?>(
      _MessageClickTargetNotifier.new,
    );

/// 按原始来源恢复离线名称快照。
final messageSourceDetailsProvider = FutureProvider.autoDispose
    .family<NotificationSource, ({String installationId, int userId})>((
      ref,
      source,
    ) async {
      final db = await ref.watch(notificationDatabaseProvider.future);
      return db.readSource(source.installationId, source.userId);
    });

/// 消息历史记录列表 Provider。
final deviceMessagesProvider = FutureProvider.autoDispose
    .family<List<NotificationMessage>, ({String installationId, int userId})>((
      ref,
      params,
    ) async {
      final db = await ref.watch(notificationDatabaseProvider.future);
      // 任意消息入库/移除都会推动 AsyncValue 更新，从而重新查询当前来源。
      ref.watch(notificationMessageChangesProvider);
      final query = ref.watch(messagesSearchQueryProvider);
      final packageFilter = ref.watch(messagesPackageFilterProvider);

      final targetId = ref.watch(targetMessageIdProvider);
      final messages = await db.queryMessages(
        params.installationId,
        params.userId,
        query: query,
        packageName: packageFilter,
        limit: 200,
      );
      // 旧横幅可能指向最近 200 条之外；仍须加载目标，且保持正常时间顺序。
      if (targetId != null &&
          query.isEmpty &&
          packageFilter == null &&
          !messages.any((m) => m.id == targetId)) {
        final target = await db.queryMessageById(
          params.installationId,
          params.userId,
          targetId,
        );
        if (target != null) {
          messages.add(target);
          messages.sort((a, b) => b.receivedTime.compareTo(a.receivedTime));
        }
      }
      return messages;
    });
