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

/// 表示应用的一张 X.509 签名证书及其指纹信息。
class AdbSignatureInfo {
  const AdbSignatureInfo({
    required this.current,
    required this.certificateVersion,
    required this.serialNumber,
    required this.subject,
    required this.issuer,
    required this.notBefore,
    required this.notAfter,
    required this.signatureAlgorithm,
    required this.publicKeyAlgorithm,
    required this.md5,
    required this.sha1,
    required this.sha256,
  });

  final bool current;
  final int certificateVersion;
  final String serialNumber;
  final String subject;
  final String issuer;
  final int notBefore;
  final int notAfter;
  final String signatureAlgorithm;
  final String publicKeyAlgorithm;
  final String md5;
  final String sha1;
  final String sha256;

  factory AdbSignatureInfo.fromJson(Map<String, Object?> json) {
    return AdbSignatureInfo(
      current: json['current'] as bool? ?? true,
      certificateVersion: json['certificateVersion'] as int? ?? 0,
      serialNumber: json['serialNumber'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      issuer: json['issuer'] as String? ?? '',
      notBefore: json['notBefore'] as int? ?? 0,
      notAfter: json['notAfter'] as int? ?? 0,
      signatureAlgorithm: json['signatureAlgorithm'] as String? ?? '',
      publicKeyAlgorithm: json['publicKeyAlgorithm'] as String? ?? '',
      md5: json['md5'] as String? ?? '',
      sha1: json['sha1'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() {
    return {
      'current': current,
      'certificateVersion': certificateVersion,
      'serialNumber': serialNumber,
      'subject': subject,
      'issuer': issuer,
      'notBefore': notBefore,
      'notAfter': notAfter,
      'signatureAlgorithm': signatureAlgorithm,
      'publicKeyAlgorithm': publicKeyAlgorithm,
      'md5': md5,
      'sha1': sha1,
      'sha256': sha256,
    };
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
    required this.signatures,
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
  final List<AdbSignatureInfo> signatures;
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
    final signatures =
        (json['signatures'] as List?)
            ?.map((e) => AdbSignatureInfo.fromJson(e as Map<String, Object?>))
            .toList() ??
        [];

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
      signatures: signatures,
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
      'signatures': signatures.map((e) => e.toJson()).toList(),
      'extractNativeLibs': extractNativeLibs,
    };
  }
}
