import 'package:flutter/material.dart';

import 'android_version_features_5.dart';
import 'android_version_features_6_7.dart';
import 'android_version_features_7_8.dart';
import 'android_version_features_9_10.dart';
import 'android_version_features_11_12.dart';
import 'android_version_features_13_14.dart';
import 'android_version_features_15_16.dart';

/// 单个功能分类下的特性列表（如 User Experience, Graphics 等），支持中英双语。
class AndroidFeatureSection {
  const AndroidFeatureSection({
    required this.title,
    this.titleZh,
    required this.items,
    this.itemsZh,
    this.columnIndex,
  });

  /// 英文分类标题 (例如 "User Experience and System UI")
  final String title;

  /// 中文分类标题 (例如 "用户体验与系统界面")
  final String? titleZh;

  /// 英文特性要点列表
  final List<String> items;

  /// 中文特性要点列表
  final List<String>? itemsZh;

  /// 显式指定所属列（0 为左列，1 为右列；若为 null 则自动按总数排版）
  final int? columnIndex;

  /// 根据语言代码返回本地化标题
  String localizedTitle(String langCode) {
    if (langCode == 'zh' && titleZh != null && titleZh!.isNotEmpty) {
      return titleZh!;
    }
    return title;
  }

  /// 根据语言代码返回本地化特性列表
  List<String> localizedItems(String langCode) {
    if (langCode == 'zh' && itemsZh != null && itemsZh!.isNotEmpty) {
      return itemsZh!;
    }
    return items;
  }
}

/// 单个 Android 版本的分布信息与新特性数据。
class AndroidDistributionItem {
  const AndroidDistributionItem({
    required this.platformVersion,
    required this.codename,
    required this.apiLevel,
    required this.cumulativeDistribution,
    required this.barColor,
    this.summaryUrl,
    this.featureSections = const [],
  });

  /// 系统主版本号 (如 "16", "15", "8.1", "5")
  final String platformVersion;

  /// 代号 (如 "B", "V", "U", "Pie", "Oreo", "Lollipop")
  final String codename;

  /// API Level (如 36, 35, 28, 21)
  final int apiLevel;

  /// 累计设备占有率百分比 (如 7.5 代表 >=该版本的设备占 7.5%)
  final double cumulativeDistribution;

  /// 图表条块显示颜色
  final Color barColor;

  /// 官方开发者版本总结链接
  final String? summaryUrl;

  /// 该版本的新特性分类列表（若暂无数据则为空列表，方便后续扩充添加）
  final List<AndroidFeatureSection> featureSections;

  /// 格式化显示的累计占比文本 (如 "7.5%")
  String get cumulativeDistributionText {
    if (cumulativeDistribution >= 100.0) {
      return '';
    }
    return '${cumulativeDistribution.toStringAsFixed(1)}%';
  }
}

/// Android 平台与 API 版本分布本地静态数据仓库。
/// 数据与 UI 分离，方便以后维护和扩展添加新的 Android 版本或特性。
class AndroidVersionDistributionData {
  AndroidVersionDistributionData._();

  /// 统计数据基准更新时间（支持中英文）
  static String localizedLastUpdatedDate(String langCode) {
    return langCode == 'zh' ? '2025年12月1日' : 'December 1, 2025';
  }

  /// 静态分布列表，按照从低版本到高版本排序
  static const List<AndroidDistributionItem> items = [
    // Android 5.0 (API 21) - 包含完整特性数据（中英双语）
    AndroidDistributionItem(
      platformVersion: '5',
      codename: 'Lollipop',
      apiLevel: 21,
      cumulativeDistribution: 100.0,
      barColor: Color(0xFFD5E0D5),
      summaryUrl: 'https://developer.android.com/about/versions/android-5.0.html',
      featureSections: kAndroid50Features,
    ),
    // Android 5.1 (API 22) - 包含完整特性数据（中英双语）
    AndroidDistributionItem(
      platformVersion: '5.1',
      codename: 'Lollipop',
      apiLevel: 22,
      cumulativeDistribution: 99.9,
      barColor: Color(0xFF60B66E),
      summaryUrl: 'https://developer.android.com/about/versions/android-5.1.html',
      featureSections: kAndroid51Features,
    ),
    // Android 6.0 (API 23) - 包含完整特性数据（中英双语）
    AndroidDistributionItem(
      platformVersion: '6',
      codename: 'Marshmallow',
      apiLevel: 23,
      cumulativeDistribution: 99.6,
      barColor: Color(0xFF99AAB3),
      summaryUrl: 'https://developer.android.com/about/versions/marshmallow/android-6.0.html',
      featureSections: kAndroid60Features,
    ),
    // Android 7.0 (API 24) - 包含完整特性数据（中英双语）
    AndroidDistributionItem(
      platformVersion: '7',
      codename: 'Nougat',
      apiLevel: 24,
      cumulativeDistribution: 99.2,
      barColor: Color(0xFFE6AF34),
      summaryUrl: 'https://developer.android.com/about/versions/nougat/android-7.0.html',
      featureSections: kAndroid70Features,
    ),
    // Android 7.1 (API 25) - 包含完整特性数据（中英双语）
    AndroidDistributionItem(
      platformVersion: '7.1',
      codename: 'Nougat',
      apiLevel: 25,
      cumulativeDistribution: 98.8,
      barColor: Color(0xFFE84D4D),
      summaryUrl: 'https://developer.android.com/about/versions/nougat/android-7.1.html',
      featureSections: kAndroid71Features,
    ),
    // Android 8.0 (API 26) - 包含完整特性数据（中英双语）
    AndroidDistributionItem(
      platformVersion: '8',
      codename: 'Oreo',
      apiLevel: 26,
      cumulativeDistribution: 98.4,
      barColor: Color(0xFF40CBE0),
      summaryUrl: 'https://developer.android.com/about/versions/oreo/android-8.0',
      featureSections: kAndroid80Features,
    ),
    // Android 8.1 (API 27) - 包含完整特性数据（中英双语）
    AndroidDistributionItem(
      platformVersion: '8.1',
      codename: 'Oreo',
      apiLevel: 27,
      cumulativeDistribution: 97.6,
      barColor: Color(0xFFDF7E56),
      summaryUrl: 'https://developer.android.com/about/versions/oreo/android-8.1',
      featureSections: kAndroid81Features,
    ),
    // Android 9 (API 28) - 包含完整特性数据（中英双语）
    AndroidDistributionItem(
      platformVersion: '9',
      codename: 'Pie',
      apiLevel: 28,
      cumulativeDistribution: 95.3,
      barColor: Color(0xFFF47B2A),
      summaryUrl: 'https://developer.android.com/about/versions/pie/android-9.0',
      featureSections: kAndroid9Features,
    ),
    // Android 10 (API 29) - 包含完整特性数据（中英双语）
    AndroidDistributionItem(
      platformVersion: '10',
      codename: 'Q',
      apiLevel: 29,
      cumulativeDistribution: 90.8,
      barColor: Color(0xFFF3A800),
      summaryUrl: 'https://developer.android.com/about/versions/10',
      featureSections: kAndroid10Features,
    ),
    // Android 11 (API 30) - 包含完整特性数据（中英双语）
    AndroidDistributionItem(
      platformVersion: '11',
      codename: 'R',
      apiLevel: 30,
      cumulativeDistribution: 83.0,
      barColor: Color(0xFFC7DEB7),
      summaryUrl: 'https://developer.android.com/about/versions/11',
      featureSections: kAndroid11Features,
    ),
    // Android 12 (API 31) - 包含完整特性数据（中英双语）
    AndroidDistributionItem(
      platformVersion: '12',
      codename: 'S',
      apiLevel: 31,
      cumulativeDistribution: 69.3,
      barColor: Color(0xFF5BC880),
      summaryUrl: 'https://developer.android.com/about/versions/12',
      featureSections: kAndroid12Features,
    ),
    // Android 13 (API 33) - 包含完整特性数据（中英双语）
    AndroidDistributionItem(
      platformVersion: '13',
      codename: 'T',
      apiLevel: 33,
      cumulativeDistribution: 57.9,
      barColor: Color(0xFF7E9DA3),
      summaryUrl: 'https://developer.android.com/about/versions/13',
      featureSections: kAndroid13Features,
    ),
    // Android 14 (API 34) - 包含完整特性数据（中英双语）
    AndroidDistributionItem(
      platformVersion: '14',
      codename: 'U',
      apiLevel: 34,
      cumulativeDistribution: 44.0,
      barColor: Color(0xFFF1B514),
      summaryUrl: 'https://developer.android.com/about/versions/14',
      featureSections: kAndroid14Features,
    ),
    // Android 15 (API 35) - 包含完整特性数据（中英双语）
    AndroidDistributionItem(
      platformVersion: '15',
      codename: 'V',
      apiLevel: 35,
      cumulativeDistribution: 26.8,
      barColor: Color(0xFFF54556),
      summaryUrl: 'https://developer.android.com/about/versions/15',
      featureSections: kAndroid15Features,
    ),
    // Android 16 (API 36) - 包含完整特性数据（中英双语）
    AndroidDistributionItem(
      platformVersion: '16',
      codename: 'B',
      apiLevel: 36,
      cumulativeDistribution: 7.5,
      barColor: Color(0xFF40C4FF),
      summaryUrl: 'https://developer.android.com/about/versions/16/summary',
      featureSections: kAndroid16Features,
    ),
  ];

  /// 根据版本号字符串或 API 级别查找匹配的条目，找不到时默认返回 Android 16
  static AndroidDistributionItem findItem(String? versionOrApi) {
    if (versionOrApi == null || versionOrApi.trim().isEmpty) {
      return items.last;
    }
    final clean = versionOrApi.trim().toLowerCase();
    for (final item in items.reversed) {
      if (clean == item.platformVersion.toLowerCase() ||
          clean == item.apiLevel.toString() ||
          clean == 'api ${item.apiLevel}' ||
          clean == 'android ${item.platformVersion}'.toLowerCase()) {
        return item;
      }
    }
    return items.last;
  }
}
