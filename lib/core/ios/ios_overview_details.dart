/// iOS 概览特有字段，仅保存白名单数据，不保留 lockdown 原始响应。
class IosOverviewDetails {
  const IosOverviewDetails({
    this.productType = '',
    this.buildVersion = '',
    this.hardwareModel = '',
    this.networkInterfaces = '',
    this.cpuCores,
    this.partial = false,
  });

  final String productType;
  final String buildVersion;
  final String hardwareModel;
  final String networkInterfaces;
  final int? cpuCores;
  final bool partial;

  Map<String, dynamic> toJson() => {
    'productType': productType,
    'buildVersion': buildVersion,
    'hardwareModel': hardwareModel,
    'networkInterfaces': networkInterfaces,
    'cpuCores': cpuCores,
    'partial': partial,
  };

  factory IosOverviewDetails.fromJson(Map<String, dynamic> json) =>
      IosOverviewDetails(
        productType: json['productType'] as String? ?? '',
        buildVersion: json['buildVersion'] as String? ?? '',
        hardwareModel: json['hardwareModel'] as String? ?? '',
        networkInterfaces: json['networkInterfaces'] as String? ?? '',
        cpuCores: json['cpuCores'] as int?,
        partial: json['partial'] as bool? ?? false,
      );
}

/// 经核对的型号规格，供 UI 明确标记“型号规格”；不作为实时设备读数。
class IosModelSpec {
  const IosModelSpec(this.name, this.chip, this.resolution, this.ppi);

  final String name;
  final String chip;
  final String resolution;
  final int ppi;

  // 来源：https://support.apple.com/en-us/111952 。未知型号不猜测参数。
  static const byProductType = {
    'iPhone8,1': IosModelSpec('iPhone 6s', 'Apple A9', '750 × 1334', 326),
  };
}
