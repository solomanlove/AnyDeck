import 'android_version_distribution_data.dart';

/// Android 17 已核验的官方资料摘要；不以预测替代发布状态。
/// 来源：https://developer.android.com/about/versions/17/behavior-changes-17
/// 核验日期：2026-10-31。完整清单以官方文档为准。
const List<AndroidFeatureSection> kAndroid17Features = [
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'For target API 37, RemoteViews widget updates enforce a bitmap memory limit. Test responsive widget sizes.',
      'For target API 37, MessageQueue uses a lock-free implementation. Check libraries that reflect on private fields.',
      'For target API 37, LAN access requires ACCESS_LOCAL_NETWORK or a supported system device picker.',
      'Test both changes for all apps and changes gated by target SDK before migration.',
    ],
    itemsZh: [
      'target API 37：RemoteViews 小组件更新强制限制位图内存，需覆盖不同尺寸的小组件回归。',
      'target API 37：MessageQueue 使用无锁实现，排查反射其私有字段的第三方库。',
      'target API 37：局域网访问需要 ACCESS_LOCAL_NETWORK，或使用支持的系统设备选择器。',
      '迁移时分别验证影响所有应用的变更和仅针对 target SDK 生效的变更。',
    ],
  ),
  AndroidFeatureSection(
    title: 'Source & verification',
    titleZh: '资料来源与核验时间',
    items: [
      'Android Developers: Android 17 overview, system images and behavior changes. Verified on 2026-10-31.',
      'Availability varies by device. The distribution snapshot date does not imply that every feature was updated on that date.',
    ],
    itemsZh: [
      '来源：Android Developers 的 Android 17 概览、系统镜像与行为变更文档。核验日期：2026-10-31。',
      '具体设备的可用性以厂商为准。分布统计快照日期不代表所有功能资料均在同日更新。',
    ],
  ),
];
