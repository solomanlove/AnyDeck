/// go-ios 返回的 iOS 应用基础信息。
class IosAppInfo {
  const IosAppInfo({
    required this.bundleId,
    required this.name,
    this.version,
    this.system = false,
    this.iconPath,
  });

  final String bundleId;
  final String name;
  final String? version;
  final bool system;
  final String? iconPath;

  IosAppInfo copyWith({
    String? bundleId,
    String? name,
    String? version,
    bool? system,
    String? iconPath,
  }) {
    return IosAppInfo(
      bundleId: bundleId ?? this.bundleId,
      name: name ?? this.name,
      version: version ?? this.version,
      system: system ?? this.system,
      iconPath: iconPath ?? this.iconPath,
    );
  }
}
