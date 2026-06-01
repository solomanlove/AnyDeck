/// 应用列表使用的已安装 Android 包元数据。
class AdbPackage {
  const AdbPackage({
    required this.name,
    this.label,
    this.apkPath,
    this.versionName,
    this.versionCode,
    this.minSdk,
    this.targetSdk,
    this.maxSdk,
    this.storageBytes,
    this.iconLocalPath,
    this.iconRemotePath,
    this.enabled = true,
    this.system = false,
    this.flutter = false,
    this.signatureMd5,
    this.firstInstallTime,
    this.lastUpdateTime,
    this.debuggable = false,
  });

  /// 包名，例如 `com.android.settings`。
  final String name;

  /// 尽力获取的展示名称；adb 无法提供时回退到 [name]。
  final String? label;

  /// 已安装 base APK 路径。
  final String? apkPath;

  final String? versionName;
  final String? versionCode;
  final int? minSdk;
  final int? targetSdk;
  final int? maxSdk;
  final int? storageBytes;
  final String? iconLocalPath;
  final String? iconRemotePath;
  final bool enabled;
  final bool system;
  final bool flutter;
  final String? signatureMd5;
  final int? firstInstallTime;
  final int? lastUpdateTime;
  final bool debuggable;

  factory AdbPackage.fromJson(Map<String, Object?> json) {
    return AdbPackage(
      name: json['name'] as String? ?? '',
      label: json['label'] as String?,
      apkPath: json['apkPath'] as String?,
      versionName: json['versionName'] as String?,
      versionCode: json['versionCode'] as String?,
      minSdk: json['minSdk'] as int?,
      targetSdk: json['targetSdk'] as int?,
      maxSdk: json['maxSdk'] as int?,
      storageBytes: json['storageBytes'] as int?,
      iconLocalPath: json['iconLocalPath'] as String?,
      iconRemotePath: json['iconRemotePath'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      system: json['system'] as bool? ?? false,
      flutter: json['flutter'] as bool? ?? false,
      signatureMd5: json['signatureMd5'] as String?,
      firstInstallTime: json['firstInstallTime'] as int?,
      lastUpdateTime: json['lastUpdateTime'] as int?,
      debuggable: json['debuggable'] as bool? ?? false,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'label': label,
      'apkPath': apkPath,
      'versionName': versionName,
      'versionCode': versionCode,
      'minSdk': minSdk,
      'targetSdk': targetSdk,
      'maxSdk': maxSdk,
      'storageBytes': storageBytes,
      'iconLocalPath': iconLocalPath,
      'iconRemotePath': iconRemotePath,
      'enabled': enabled,
      'system': system,
      'flutter': flutter,
      'signatureMd5': signatureMd5,
      'firstInstallTime': firstInstallTime,
      'lastUpdateTime': lastUpdateTime,
      'debuggable': debuggable,
    };
  }

  AdbPackage copyWith({
    String? label,
    String? iconLocalPath,
    String? iconRemotePath,
    String? signatureMd5,
    int? firstInstallTime,
    int? lastUpdateTime,
    bool? debuggable,
  }) {
    return AdbPackage(
      name: name,
      label: label ?? this.label,
      apkPath: apkPath,
      versionName: versionName,
      versionCode: versionCode,
      minSdk: minSdk,
      targetSdk: targetSdk,
      maxSdk: maxSdk,
      storageBytes: storageBytes,
      iconLocalPath: iconLocalPath ?? this.iconLocalPath,
      iconRemotePath: iconRemotePath ?? this.iconRemotePath,
      enabled: enabled,
      system: system,
      flutter: flutter,
      signatureMd5: signatureMd5 ?? this.signatureMd5,
      firstInstallTime: firstInstallTime ?? this.firstInstallTime,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      debuggable: debuggable ?? this.debuggable,
    );
  }

  String get displayName {
    final value = label?.trim();
    return value == null || value.isEmpty ? name : value;
  }

  String get versionLabel {
    final namePart = versionName?.trim();
    if (namePart != null && namePart.isNotEmpty) {
      return namePart;
    }
    final codePart = versionCode?.trim();
    return codePart == null || codePart.isEmpty ? '-' : codePart;
  }

  String get storageLabel {
    final bytes = storageBytes;
    if (bytes == null || bytes <= 0) {
      return '-';
    }
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)}G';
    }
    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(2)}M';
    }
    if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(1)}K';
    }
    return '${bytes}B';
  }
}
