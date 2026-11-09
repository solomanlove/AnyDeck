import 'device_share_invitation.dart';
import 'share_tls_identity.dart';

/// 共享授权窗口；永久仅表示不创建会话到期计时器。
enum DeviceShareLifetime {
  minutes30,
  hour1,
  unlimited;

  Duration? get duration => switch (this) {
    minutes30 => const Duration(minutes: 30),
    hour1 => const Duration(hours: 1),
    unlimited => null,
  };

  String get labelKey => 'deviceShareLifetime_$name';

  static DeviceShareLifetime parse(Object? value) =>
      values.where((entry) => entry.name == value).firstOrNull ?? minutes30;
}

/// 分享方保存的单设备规则与私有身份；仅写入应用私有存储，不进入普通设置或日志。
class SavedDeviceShare {
  const SavedDeviceShare({
    required this.deviceId,
    required this.serial,
    required this.name,
    required this.identity,
    required this.token,
    this.lifetime = DeviceShareLifetime.minutes30,
    this.wifiSsid,
    this.enabled = true,
    this.lastHost,
    this.lastPort = 0,
  });

  final String deviceId, serial, name, token;
  final ShareTlsIdentity identity;
  final DeviceShareLifetime lifetime;
  final String? wifiSsid, lastHost;
  final bool enabled;
  final int lastPort;
  String get id => identity.fingerprint;
  bool get automaticallyPrepares => enabled && wifiSsid != null;

  SavedDeviceShare copyWith({
    String? deviceId,
    String? serial,
    String? name,
    DeviceShareLifetime? lifetime,
    String? wifiSsid,
    bool clearWifi = false,
    bool? enabled,
    String? lastHost,
    int? lastPort,
  }) => SavedDeviceShare(
    deviceId: deviceId ?? this.deviceId,
    serial: serial ?? this.serial,
    name: name ?? this.name,
    identity: identity,
    token: token,
    lifetime: lifetime ?? this.lifetime,
    wifiSsid: clearWifi ? null : wifiSsid ?? this.wifiSsid,
    enabled: enabled ?? this.enabled,
    lastHost: lastHost ?? this.lastHost,
    lastPort: lastPort ?? this.lastPort,
  );

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'serial': serial,
    'name': name,
    'certificate': identity.certificate,
    'privateKey': identity.privateKey,
    'token': token,
    'lifetime': lifetime.name,
    'wifiSsid': wifiSsid,
    'enabled': enabled,
    'lastHost': lastHost,
    'lastPort': lastPort,
  };

  factory SavedDeviceShare.fromJson(Map<String, dynamic> json) {
    final identity = ShareTlsIdentity(
      json['certificate'] as String,
      json['privateKey'] as String,
    );
    // 复用分享码校验，拒绝损坏或被拼成其他协议的历史地址和凭据。
    DeviceShareInvitation.parse(
      DeviceShareInvitation(
        host: json['lastHost'] as String? ?? '127.0.0.1',
        port: (json['lastPort'] as int? ?? 0).clamp(1, 65535),
        fingerprint: identity.fingerprint,
        token: json['token'] as String,
        name: json['name'] as String,
      ).encode(),
    );
    return SavedDeviceShare(
      deviceId: json['deviceId'] as String,
      serial: json['serial'] as String,
      name: json['name'] as String,
      identity: identity,
      token: json['token'] as String,
      lifetime: DeviceShareLifetime.parse(json['lifetime']),
      wifiSsid: (json['wifiSsid'] as String?)?.isNotEmpty == true
          ? json['wifiSsid'] as String
          : null,
      enabled: json['enabled'] == true,
      lastHost: json['lastHost'] as String?,
      lastPort: json['lastPort'] as int? ?? 0,
    );
  }
}

/// 接收方历史记录；断开后保留重连凭据，不再以离线设备占据设备管理列表。
class DeviceShareHistoryEntry {
  const DeviceShareHistoryEntry(this.invitation, this.lastConnectedAt);
  final DeviceShareInvitation invitation;
  final DateTime lastConnectedAt;
  String get id => invitation.fingerprint;

  Map<String, Object?> toJson() => {
    'code': invitation.encode(),
    'lastConnectedAt': lastConnectedAt.toUtc().toIso8601String(),
  };

  factory DeviceShareHistoryEntry.fromJson(Map<String, dynamic> json) =>
      DeviceShareHistoryEntry(
        DeviceShareInvitation.parse(json['code'] as String),
        DateTime.parse(json['lastConnectedAt'] as String).toUtc(),
      );
}

/// 原子保存规则与接收历史，避免并发更新互相覆盖。
class DeviceShareSavedState {
  const DeviceShareSavedState({
    this.profiles = const [],
    this.history = const [],
  });
  final List<SavedDeviceShare> profiles;
  final List<DeviceShareHistoryEntry> history;

  Map<String, Object?> toJson() => {
    'version': 1,
    'profiles': profiles.map((entry) => entry.toJson()).toList(),
    'history': history.map((entry) => entry.toJson()).toList(),
  };

  factory DeviceShareSavedState.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Invalid share store');
    }
    List<T> read<T>(String key, T Function(Map<String, dynamic>) parse) => [
      for (final value in json[key] as List? ?? [])
        if (value is Map<String, dynamic>)
          ...(() {
            try {
              return [parse(value)];
            } catch (_) {
              return <T>[];
            }
          })(),
    ];
    return DeviceShareSavedState(
      profiles: read('profiles', SavedDeviceShare.fromJson),
      history: read(
        'history',
        DeviceShareHistoryEntry.fromJson,
      ).take(50).toList(),
    );
  }
}
