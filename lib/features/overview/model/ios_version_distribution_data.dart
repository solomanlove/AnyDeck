// iOS 版本采用率与工具链矩阵数据模型。
// 数据来源：Apple Developer「iOS 和 iPadOS 使用情况」官方统计与 TelemetryDeck 遥测快照。

/// 工具链矩阵键值对
class IosToolchainMatrixEntry {
  const IosToolchainMatrixEntry({
    required this.key,
    required this.value,
  });

  /// 属性名（如 Xcode, Swift, SDK, 部署目标范围）
  final String key;

  /// 属性值（如 27 / 27.1 beta, Swift 6.4）
  final String value;
}

/// iOS 版本分布条目
class IosDistributionItem {
  const IosDistributionItem({
    required this.version,
    required this.minor,
    required this.date,
    required this.badgeType,
    required this.badgeText,
    required this.share,
    required this.sharePercent,
    required this.source,
    required this.summary,
    required this.matrix,
    required this.impacts,
    required this.core,
    required this.privacy,
    required this.link,
  });

  /// 大版本名称（如 27, 26, 18, ≤17）
  final String version;

  /// 次版本或说明（如 27.0, 26.x, 17 及更早）
  final String minor;

  /// 发布时间（如 2026-09, 2025-09）
  final String date;

  /// 徽章类型标识：'current', 'previous', 'historical'
  final String badgeType;

  /// 徽章文本（如 最新, 前代, 历史）
  final String badgeText;

  /// 展现的设备占比文本（如 16.4%, 79%, 约 11%）
  final String share;

  /// 数值型设备占比（用于柱状图计算，满刻度基准约为 79.0）
  final double sharePercent;

  /// 数据来源说明（如 Apple 官方, 第三方）
  final String source;

  /// 概要说明文字
  final String summary;

  /// 工具链对应矩阵列表
  final List<IosToolchainMatrixEntry> matrix;

  /// 编译与适配要求要点
  final List<String> impacts;

  /// 平台核心与 AI 能力
  final List<String> core;

  /// 安全与隐私保护特性
  final List<String> privacy;

  /// Apple 官方文档链接
  final String link;
}

/// iOS 历史版本条目（1.0 ~ 17）
class IosHistItem {
  const IosHistItem({
    required this.version,
    required this.releaseDate,
    required this.xcode,
    required this.swift,
    required this.status,
  });

  /// 版本号（如 17, 16 ... 1.0）
  final String version;

  /// 发布时间（如 2023-09）
  final String releaseDate;

  /// 兼容 Xcode 工具链版本
  final String xcode;

  /// 匹配 Swift 语言版本
  final String swift;

  /// 状态说明（如 已 EOL）
  final String status;
}

/// iOS 版本分布与工具链数据仓库
class IosVersionDistributionData {
  IosVersionDistributionData._();

  /// 主力支持版本列表
  static const List<IosDistributionItem> items = [
    IosDistributionItem(
      version: '27',
      minor: '27.0',
      date: '2026-09',
      badgeType: 'current',
      badgeText: '最新',
      share: '16.4%',
      sharePercent: 16.4,
      source: '第三方',
      summary:
          '最新大版本，2026 年 9 月正式发布，2026-09-30 快照口径下已约 16.4% 设备升级。',
      matrix: [
        IosToolchainMatrixEntry(key: 'Xcode', value: '27 / 27.1 beta / 27.2 beta'),
        IosToolchainMatrixEntry(key: 'Swift', value: '6.4'),
        IosToolchainMatrixEntry(key: 'SDK', value: 'iOS 27'),
        IosToolchainMatrixEntry(key: '部署目标范围', value: 'iOS 15 – 27'),
        IosToolchainMatrixEntry(key: '模拟器支持', value: 'iOS 17 及以上'),
        IosToolchainMatrixEntry(key: '语言模式', value: 'Swift 6 / 5 / 4.2 / 4'),
      ],
      impacts: [
        '工具链：Xcode 27 需 macOS Tahoe 26.4 或更高版本，团队需统一升级开发机。',
        '编译语言：编译器为 Swift 6.4，推荐开启 Swift 6 严格并发语言模式。',
        'Liquid Glass 在 iOS 27 中继续演进，若沿用 iOS 26 的 glassEffect，版本守卫仍应写 iOS 26，写 27 会让 iOS 26 设备静默降级。',
        'App 可调整性：用 iOS 27 SDK 重新构建即自动生效，无需 opt-in；任何假设固定宽度的布局都会在无代码变更的情况下破版，回归测试须覆盖 iPad 与 iPhone 镜像。',
      ],
      core: [
        '端侧 AI / 私有化云端模型语言能力扩展',
        'iPad 与 iPhone 镜像应用可调整性',
        '系统内置工具（OCR、条码识别）开放',
      ],
      privacy: [
        '系统级权限透明度进一步提升',
        'App 隐私报告数据口径细化',
      ],
      link: 'https://developer.apple.com/cn/support/app-store',
    ),
    IosDistributionItem(
      version: '26',
      minor: '26.x',
      date: '2025-09',
      badgeType: 'previous',
      badgeText: '前代',
      share: '79%',
      sharePercent: 79.0,
      source: 'Apple 官方',
      summary:
          'Apple 官方采用率（统计基准日 2026-06-07）：iOS 26 占全部 iPhone 的 79%，近四年推出的 iPhone 中达 86%；iPadOS 26 占全部 iPad 的 68%，近四年机型为 79%。',
      matrix: [
        IosToolchainMatrixEntry(
          key: 'Xcode',
          value: '26.2 / 26.3 / 26.4 / 26.4.1 / 26.5 / 26.6',
        ),
        IosToolchainMatrixEntry(key: 'Swift', value: '6.0 – 6.3'),
        IosToolchainMatrixEntry(key: 'SDK', value: 'iOS 26.x'),
        IosToolchainMatrixEntry(key: '部署目标范围', value: 'iOS 15 – 26.x'),
        IosToolchainMatrixEntry(key: '模拟器支持', value: 'iOS 15 及以上'),
        IosToolchainMatrixEntry(key: '语言模式', value: 'Swift 6 / 5 / 4.2 / 4'),
      ],
      impacts: [
        '版本分布：第三方快照（2026-09-30）显示 26.6 约 51.2%、26.5 约 17.6%，小版本碎片化程度高于 iOS 27 发布初期。',
        'Liquid Glass：需用 @available(iOS 26, *) 包裹 glassEffect / GlassEffectContainer / glassEffectID 等新符号。',
        'Foundation Models 框架基线：SystemLanguageModel / LanguageModelSession / @Generable 均需 iOS 26 守卫。',
        'iPad 采纳明显滞后：比 iPhone 低约 11 个百分点，测试矩阵应单独为 iPad 设定。',
      ],
      core: [
        'Liquid Glass 设计语言',
        'Foundation Models 框架基线',
        '系统级搜索与 TabView 新 API',
      ],
      privacy: [
        'App Store 隐私清单细化',
        '权限用途声明强制化',
      ],
      link: 'https://developer.apple.com/cn/support/app-store',
    ),
    IosDistributionItem(
      version: '18',
      minor: '18.x',
      date: '2024-09',
      badgeType: 'historical',
      badgeText: '历史',
      share: '约 11%',
      sharePercent: 11.0,
      source: 'Apple 官方',
      summary:
          'iOS 18 在全部 iPhone 中约占 11%（与 iOS 26 合计约 90%），目前已退出主流支持窗口。',
      matrix: [
        IosToolchainMatrixEntry(key: 'Xcode', value: '16'),
        IosToolchainMatrixEntry(key: 'Swift', value: '6.0 – 6.1'),
        IosToolchainMatrixEntry(key: 'SDK', value: 'iOS 18.x'),
        IosToolchainMatrixEntry(key: '部署目标范围', value: 'iOS 15 – 18.x'),
        IosToolchainMatrixEntry(key: '模拟器支持', value: 'iOS 17 及以上'),
        IosToolchainMatrixEntry(key: '语言模式', value: 'Swift 6 / 5'),
      ],
      impacts: [
        'MeshGradient / TextRenderer / 缩放式导航转场均需 @available(iOS 18, *) 守卫。',
        'SwiftData History API、@Index 需 iOS 18 守卫。',
        '定位：已属长尾，测试投入应显著低于 iOS 26 / 27。',
      ],
      core: [
        'SwiftData 成熟化',
        '控制中心小组件',
        '网格渐变与文本渲染能力',
      ],
      privacy: [
        '权限请求频率与合理性审查趋严',
      ],
      link: 'https://developer.apple.com/cn/support/app-store',
    ),
    IosDistributionItem(
      version: '≤17',
      minor: '17 及更早',
      date: '≤2023-09',
      badgeType: 'historical',
      badgeText: '历史',
      share: '约 7%',
      sharePercent: 7.0,
      source: 'Apple 官方',
      summary:
          'iOS 17 及更早版本合计约 7%。Apple 从未公布各历史版本的具体占比，此处仅有汇总值。',
      matrix: [
        IosToolchainMatrixEntry(key: 'Xcode', value: '15 及更早'),
        IosToolchainMatrixEntry(key: 'Swift', value: '5.9 及更早'),
        IosToolchainMatrixEntry(key: 'SDK', value: 'iOS 17.x 及更早'),
        IosToolchainMatrixEntry(key: '部署目标范围', value: 'Xcode 27 已不再支持 iOS 15 以下'),
        IosToolchainMatrixEntry(key: '模拟器支持', value: '—'),
        IosToolchainMatrixEntry(key: '语言模式', value: 'Swift 5 / 4.2'),
      ],
      impacts: [
        '工具链硬约束：Xcode 27 的部署目标范围为 iOS 15 – 27，已不支持 iOS 15 以下的设备。',
        '实践基线建议：若使用 @Observable / SwiftData / NavigationStack / #Preview 等能力，最低需 iOS 17。',
        '明确的版本守卫原则：按符号引入的版本做守卫，绝不要按「当前使用的 SDK」写版本号，否则会静默丢弃旧版本设备。',
      ],
      core: [
        'SwiftData、Observation、NavigationStack、#Preview 基线能力',
      ],
      privacy: [
        '系统沙盒访问防护',
      ],
      link: 'https://developer.apple.com/cn/support/app-store',
    ),
  ];

  /// 历史版本列表（1.0 起）
  static const List<IosHistItem> historyItems = [
    IosHistItem(version: '17', releaseDate: '2023-09', xcode: 'Xcode 15', swift: 'Swift 5.9', status: '已 EOL'),
    IosHistItem(version: '16', releaseDate: '2022-09', xcode: 'Xcode 14', swift: 'Swift 5.7', status: '已 EOL'),
    IosHistItem(version: '15', releaseDate: '2021-09', xcode: 'Xcode 13', swift: 'Swift 5.5', status: '已 EOL'),
    IosHistItem(version: '14', releaseDate: '2020-09', xcode: 'Xcode 12', swift: 'Swift 5.3', status: '已 EOL'),
    IosHistItem(version: '13', releaseDate: '2019-09', xcode: 'Xcode 11', swift: 'Swift 5.1', status: '已 EOL'),
    IosHistItem(version: '12', releaseDate: '2018-09', xcode: 'Xcode 10', swift: 'Swift 5.0', status: '已 EOL'),
    IosHistItem(version: '11', releaseDate: '2017-09', xcode: 'Xcode 9', swift: 'Swift 4', status: '已 EOL'),
    IosHistItem(version: '10', releaseDate: '2016-09', xcode: 'Xcode 8', swift: 'Swift 3', status: '已 EOL'),
    IosHistItem(version: '9', releaseDate: '2015-09', xcode: 'Xcode 7', swift: 'Swift 2', status: '已 EOL'),
    IosHistItem(version: '8', releaseDate: '2014-09', xcode: 'Xcode 6', swift: 'Swift 1', status: '已 EOL'),
    IosHistItem(version: '7', releaseDate: '2013-09', xcode: 'Xcode 5', swift: '—', status: '已 EOL'),
    IosHistItem(version: '6', releaseDate: '2012-09', xcode: 'Xcode 4.3', swift: '—', status: '已 EOL'),
    IosHistItem(version: '5', releaseDate: '2011-10', xcode: 'Xcode 4.2', swift: '—', status: '已 EOL'),
    IosHistItem(version: '4', releaseDate: '2010-06', xcode: 'Xcode 4', swift: '—', status: '已 EOL'),
    IosHistItem(version: '3', releaseDate: '2009-06', xcode: 'Xcode 3', swift: '—', status: '已 EOL'),
    IosHistItem(version: '2', releaseDate: '2008-07', xcode: 'Xcode 2.5', swift: '—', status: '已 EOL'),
    IosHistItem(version: '1.0', releaseDate: '2007-06', xcode: '—', swift: '—', status: '已 EOL'),
  ];
}
