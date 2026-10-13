/// 跨平台版本与生态分布所支持的平台类型枚举与元数据定义。
enum PlatformDistributionType {
  /// Android 平台与 API 版本分布
  android,

  /// HarmonyOS 鸿蒙版本与 API 版本分布
  harmony,

  /// Apple iOS 版本采用率与工具链分布
  ios,
}

/// 平台元数据与配置扩展
extension PlatformDistributionTypeExt on PlatformDistributionType {
  /// 平台的英文标识符
  String get id {
    switch (this) {
      case PlatformDistributionType.android:
        return 'android';
      case PlatformDistributionType.harmony:
        return 'harmony';
      case PlatformDistributionType.ios:
        return 'ios';
    }
  }

  /// 平台的显示名称
  String get displayName {
    switch (this) {
      case PlatformDistributionType.android:
        return 'Android';
      case PlatformDistributionType.harmony:
        return 'HarmonyOS';
      case PlatformDistributionType.ios:
        return 'iOS';
    }
  }

  /// 标题本地化对应的 key
  String get titleL10nKey {
    switch (this) {
      case PlatformDistributionType.android:
        return 'androidApiDistribution';
      case PlatformDistributionType.harmony:
        return 'harmonyApiDistribution';
      case PlatformDistributionType.ios:
        return 'iosApiDistribution';
    }
  }

  /// 数据快照更新时间
  String get lastUpdatedDate {
    switch (this) {
      case PlatformDistributionType.android:
        return '2026-10-13';
      case PlatformDistributionType.harmony:
        return '2026-10-07';
      case PlatformDistributionType.ios:
        return '2026-06-07';
    }
  }

  /// 数据口径与来源提示文案（中文）
  String get flagNoticeZh {
    switch (this) {
      case PlatformDistributionType.android:
        return '示意数据 · 正式版需切 Play Console 自有数据';
      case PlatformDistributionType.harmony:
        return '华为官网存量 API 占比 · 约 15 天更新';
      case PlatformDistributionType.ios:
        return 'Apple 官方采用率 · iOS 27 为第三方快照';
    }
  }

  /// 数据口径与来源提示文案（英文）
  String get flagNoticeEn {
    switch (this) {
      case PlatformDistributionType.android:
        return 'Sample data · Switch to Play Console for production';
      case PlatformDistributionType.harmony:
        return 'Huawei official API share · Updated every ~15 days';
      case PlatformDistributionType.ios:
        return 'Apple official adoption · iOS 27 third-party snapshot';
    }
  }

  /// 根据语言代码返回提示文案
  String localizedFlagNotice(String langCode) {
    return langCode.toLowerCase().startsWith('zh') ? flagNoticeZh : flagNoticeEn;
  }
}
