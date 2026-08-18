/// 表示应用组件（活动、服务、接收器、提供者）的详细元数据。
class AdbComponentInfo {
  const AdbComponentInfo({
    required this.name,
    required this.exported,
    this.permission,
    this.authority,
  });

  final String name;
  final bool exported;
  final String? permission;
  final String? authority;

  factory AdbComponentInfo.fromJson(Map<String, Object?> json) {
    return AdbComponentInfo(
      name: json['name'] as String? ?? '',
      exported: json['exported'] as bool? ?? false,
      permission: json['permission'] as String?,
      authority: json['authority'] as String?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'exported': exported,
      'permission': permission,
      'authority': authority,
    };
  }

  String get shortName {
    final idx = name.lastIndexOf('.');
    if (idx >= 0 && idx < name.length - 1) {
      return name.substring(idx + 1);
    }
    return name;
  }
}

/// 表示单个 DEX 文件的信息。
class AdbDexFileInfo {
  const AdbDexFileInfo({required this.name, required this.size});

  final String name;
  final int size;

  factory AdbDexFileInfo.fromJson(Map<String, Object?> json) {
    return AdbDexFileInfo(
      name: json['name'] as String? ?? '',
      size: json['size'] as int? ?? 0,
    );
  }

  Map<String, Object?> toJson() {
    return {'name': name, 'size': size};
  }
}

/// 表示单个申请权限的信息及其授权状态。
class AdbPermissionInfo {
  const AdbPermissionInfo({required this.name, required this.granted});

  final String name;
  final bool granted;

  factory AdbPermissionInfo.fromJson(Map<String, Object?> json) {
    return AdbPermissionInfo(
      name: json['name'] as String? ?? '',
      granted: json['granted'] as bool? ?? false,
    );
  }

  Map<String, Object?> toJson() {
    return {'name': name, 'granted': granted};
  }

  String get shortName {
    final idx = name.lastIndexOf('.');
    if (idx >= 0 && idx < name.length - 1) {
      return name.substring(idx + 1);
    }
    return name;
  }
}

/// 表示应用的详细 LibChecker 元数据。
class AdbPackageDetail {
  const AdbPackageDetail({
    required this.packageName,
    this.primaryCpuAbi,
    this.secondaryCpuAbi,
    required this.supportedAbis,
    required this.frameworks,
    required this.libs,
    required this.dexFiles,
    required this.activities,
    required this.services,
    required this.receivers,
    required this.providers,
    required this.permissions,
    required this.metadata,
    required this.signatureMd5,
    this.extractNativeLibs,
  });

  final String packageName;
  final String? primaryCpuAbi;
  final String? secondaryCpuAbi;
  final List<String> supportedAbis;
  final List<String> frameworks;
  final List<String> libs;
  final List<AdbDexFileInfo> dexFiles;
  final List<AdbComponentInfo> activities;
  final List<AdbComponentInfo> services;
  final List<AdbComponentInfo> receivers;
  final List<AdbComponentInfo> providers;
  final List<AdbPermissionInfo> permissions;
  final Map<String, String> metadata;
  final String signatureMd5;
  final bool? extractNativeLibs;

  factory AdbPackageDetail.fromJson(Map<String, Object?> json) {
    final abis = (json['supportedAbis'] as List?)?.cast<String>() ?? [];
    final fws = (json['frameworks'] as List?)?.cast<String>() ?? [];
    final libraries = (json['libs'] as List?)?.cast<String>() ?? [];

    final dexList =
        (json['dexFiles'] as List?)
            ?.map((e) => AdbDexFileInfo.fromJson(e as Map<String, Object?>))
            .toList() ??
        [];

    final acts =
        (json['activities'] as List?)
            ?.map((e) => AdbComponentInfo.fromJson(e as Map<String, Object?>))
            .toList() ??
        [];

    final srvs =
        (json['services'] as List?)
            ?.map((e) => AdbComponentInfo.fromJson(e as Map<String, Object?>))
            .toList() ??
        [];

    final rcvs =
        (json['receivers'] as List?)
            ?.map((e) => AdbComponentInfo.fromJson(e as Map<String, Object?>))
            .toList() ??
        [];

    final prvs =
        (json['providers'] as List?)
            ?.map((e) => AdbComponentInfo.fromJson(e as Map<String, Object?>))
            .toList() ??
        [];

    final perms =
        (json['permissions'] as List?)
            ?.map((e) => AdbPermissionInfo.fromJson(e as Map<String, Object?>))
            .toList() ??
        [];

    final meta = (json['metadata'] as Map?)?.cast<String, String>() ?? {};

    return AdbPackageDetail(
      packageName: json['packageName'] as String? ?? '',
      primaryCpuAbi: json['primaryCpuAbi'] as String?,
      secondaryCpuAbi: json['secondaryCpuAbi'] as String?,
      supportedAbis: abis,
      frameworks: fws,
      libs: libraries,
      dexFiles: dexList,
      activities: acts,
      services: srvs,
      receivers: rcvs,
      providers: prvs,
      permissions: perms,
      metadata: meta,
      signatureMd5: json['signatureMd5'] as String? ?? '',
      extractNativeLibs: json['extractNativeLibs'] as bool?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'packageName': packageName,
      'primaryCpuAbi': primaryCpuAbi,
      'secondaryCpuAbi': secondaryCpuAbi,
      'supportedAbis': supportedAbis,
      'frameworks': frameworks,
      'libs': libs,
      'dexFiles': dexFiles.map((e) => e.toJson()).toList(),
      'activities': activities.map((e) => e.toJson()).toList(),
      'services': services.map((e) => e.toJson()).toList(),
      'receivers': receivers.map((e) => e.toJson()).toList(),
      'providers': providers.map((e) => e.toJson()).toList(),
      'permissions': permissions.map((e) => e.toJson()).toList(),
      'metadata': metadata,
      'signatureMd5': signatureMd5,
      'extractNativeLibs': extractNativeLibs,
    };
  }
}
