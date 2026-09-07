/// go-ios 返回的 iOS 应用基础信息。
class IosAppInfo {
  const IosAppInfo({
    required this.bundleId,
    required this.name,
    this.version,
    this.system = false,
  });

  final String bundleId;
  final String name;
  final String? version;
  final bool system;
}
