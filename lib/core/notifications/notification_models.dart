/// 手机转发消息的数据模型定义。
class NotificationMessage {
  const NotificationMessage({
    this.id,
    required this.installationId,
    required this.androidUserId,
    required this.notificationKey,
    required this.packageName,
    this.appName,
    required this.title,
    required this.content,
    required this.postTime,
    required this.receivedTime,
    this.isRemoved = false,
  });

  final int? id;
  final String installationId;
  final int androidUserId;
  final String notificationKey;
  final String packageName;
  final String? appName;
  final String title;
  final String content;
  final DateTime postTime;
  final DateTime receivedTime;
  final bool isRemoved;

  NotificationMessage copyWith({
    int? id,
    String? installationId,
    int? androidUserId,
    String? notificationKey,
    String? packageName,
    String? appName,
    String? title,
    String? content,
    DateTime? postTime,
    DateTime? receivedTime,
    bool? isRemoved,
  }) {
    return NotificationMessage(
      id: id ?? this.id,
      installationId: installationId ?? this.installationId,
      androidUserId: androidUserId ?? this.androidUserId,
      notificationKey: notificationKey ?? this.notificationKey,
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      title: title ?? this.title,
      content: content ?? this.content,
      postTime: postTime ?? this.postTime,
      receivedTime: receivedTime ?? this.receivedTime,
      isRemoved: isRemoved ?? this.isRemoved,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'installation': installationId,
      'user_id': androidUserId,
      'notification_key': notificationKey,
      'package_name': packageName,
      'app_name': appName,
      'title': title,
      'content': content,
      'post_time': postTime.millisecondsSinceEpoch,
      'received_time': receivedTime.millisecondsSinceEpoch,
      'is_removed': isRemoved ? 1 : 0,
    };
  }

  factory NotificationMessage.fromMap(Map<String, dynamic> map) {
    return NotificationMessage(
      id: map['id'] as int?,
      installationId: map['installation'] as String,
      androidUserId: map['user_id'] as int,
      notificationKey: map['notification_key'] as String,
      packageName: map['package_name'] as String,
      appName: map['app_name'] as String?,
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      postTime: DateTime.fromMillisecondsSinceEpoch(map['post_time'] as int),
      receivedTime:
          DateTime.fromMillisecondsSinceEpoch(map['received_time'] as int),
      isRemoved: (map['is_removed'] as int? ?? 0) != 0,
    );
  }
}

/// 已知物理设备路由与 Companion 安装实例的持久化关联。
class NotificationSource {
  const NotificationSource({
    required this.installationId,
    required this.androidUserId,
  });

  final String installationId;
  final int androidUserId;
}

/// 通知存储变化事件，供消息列表按来源实时刷新。
class NotificationStoreChange {
  const NotificationStoreChange({
    required this.installationId,
    required this.androidUserId,
    required this.deviceId,
  });

  final String installationId;
  final int androidUserId;
  final String deviceId;

  bool matches(String installationId, int androidUserId) =>
      this.installationId == installationId &&
      this.androidUserId == androidUserId;
}

/// 手机端 Companion 通知监听状态模型。
class NotificationSessionStatus {
  const NotificationSessionStatus({
    required this.isSharingEnabled,
    required this.isPermissionGranted,
    required this.installationId,
    required this.androidUserId,
    this.rawStatus = 'ok',
  });

  final bool isSharingEnabled;
  final bool isPermissionGranted;
  final String installationId;
  final int androidUserId;
  final String rawStatus;

  bool get isReady =>
      rawStatus == 'ok' && isSharingEnabled && isPermissionGranted;
}

/// 单次轮询增量收到的通知事件。
class NotificationEvent {
  const NotificationEvent({
    required this.event,
    required this.key,
    required this.packageName,
    this.title = '',
    this.content = '',
    required this.postTime,
    required this.sequence,
  });

  final String event; // 'posted' | 'removed'
  final String key;
  final String packageName;
  final String title;
  final String content;
  final DateTime postTime;
  final int sequence;

  factory NotificationEvent.fromJson(Map<String, dynamic> json) {
    return NotificationEvent(
      event: json['event'] as String? ?? 'posted',
      key: json['key'] as String? ?? '',
      packageName: json['packageName'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      postTime: DateTime.fromMillisecondsSinceEpoch(
        (json['postTime'] as num?)?.toInt() ?? 0,
      ),
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
    );
  }
}
