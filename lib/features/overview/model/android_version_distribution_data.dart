import 'package:flutter/material.dart';

import 'android_version_features_1_to_3.dart';
import 'android_version_features_4.dart';
import 'android_version_features_5.dart';
import 'android_version_features_6_7.dart';
import 'android_version_features_7_8.dart';
import 'android_version_features_9_10.dart';
import 'android_version_features_11_12.dart';
import 'android_version_features_13_14.dart';
import 'android_version_features_15_16.dart';
import 'android_version_features_17.dart';

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
    this.releaseDateZh = '',
    this.releaseDateEn = '',
    this.summaryUrl,
    this.featureSections = const [],
  });

  /// 系统主版本号 (如 "17", "16", "15", "8.1", "4.4", "1.0")
  final String platformVersion;

  /// 代号 (如 "C", "B", "V", "KitKat", "Lollipop")
  final String codename;

  /// API Level (如 37, 36, 35, 19, 1)
  final int apiLevel;

  /// 累计设备占有率百分比 (如 7.5 代表 >=该版本的设备占 7.5%)
  final double cumulativeDistribution;

  /// 图表条块显示颜色
  final Color barColor;

  /// 稳定版发布时间（中文，如 "2024年10月15日"）
  final String releaseDateZh;

  /// 稳定版发布时间（英文，如 "October 15, 2024"）
  final String releaseDateEn;

  /// 官方开发者版本总结链接
  final String? summaryUrl;

  /// 该版本的新特性分类列表（包含开发影响与适配要求）
  final List<AndroidFeatureSection> featureSections;

  /// 格式化显示的累计占比文本 (如 "7.5%")
  String get cumulativeDistributionText {
    if (cumulativeDistribution >= 100.0) {
      return '';
    }
    return '${cumulativeDistribution.toStringAsFixed(1)}%';
  }

  /// 本地化稳定版上线时间
  String localizedReleaseDate(String langCode) {
    if (langCode == 'zh' && releaseDateZh.isNotEmpty) {
      return releaseDateZh;
    }
    return releaseDateEn.isNotEmpty ? releaseDateEn : releaseDateZh;
  }
}

/// Android 平台与 API 版本分布本地静态数据仓库。
/// 数据与 UI 分离，包含 Android 1.0 到 Android 17 全量版本数据。
class AndroidVersionDistributionData {
  AndroidVersionDistributionData._();

  /// 统计数据基准更新时间（支持中英文）
  static String localizedLastUpdatedDate(String langCode) {
    return langCode == 'zh' ? '2025年12月1日' : 'December 1, 2025';
  }

  /// 静态分布列表，按照从低版本到高版本排序
  static const List<AndroidDistributionItem> items = [
    // Android 1.0 (API 1)
    AndroidDistributionItem(
      platformVersion: '1.0',
      codename: 'Base',
      apiLevel: 1,
      cumulativeDistribution: 100.0,
      barColor: Color(0xFFAED581),
      releaseDateZh: '2008年9月23日',
      releaseDateEn: 'September 23, 2008',
      summaryUrl: 'https://developer.android.com/about/versions',
      featureSections: kAndroid10BaseFeatures,
    ),
    // Android 1.5 (API 3)
    AndroidDistributionItem(
      platformVersion: '1.5',
      codename: 'Cupcake',
      apiLevel: 3,
      cumulativeDistribution: 100.0,
      barColor: Color(0xFF81C784),
      releaseDateZh: '2009年4月27日',
      releaseDateEn: 'April 27, 2009',
      summaryUrl: 'https://developer.android.com/about/versions',
      featureSections: kAndroid15CupcakeFeatures,
    ),
    // Android 1.6 (API 4)
    AndroidDistributionItem(
      platformVersion: '1.6',
      codename: 'Donut',
      apiLevel: 4,
      cumulativeDistribution: 100.0,
      barColor: Color(0xFF4DB6AC),
      releaseDateZh: '2009年9月15日',
      releaseDateEn: 'September 15, 2009',
      summaryUrl: 'https://developer.android.com/about/versions/android-1.6-highlights',
      featureSections: kAndroid16DonutFeatures,
    ),
    // Android 2.0 (API 5)
    AndroidDistributionItem(
      platformVersion: '2.0',
      codename: 'Eclair',
      apiLevel: 5,
      cumulativeDistribution: 100.0,
      barColor: Color(0xFF4DD0E1),
      releaseDateZh: '2009年10月27日',
      releaseDateEn: 'October 27, 2009',
      summaryUrl: 'https://developer.android.com/about/versions/android-2.0-highlights',
      featureSections: kAndroid20Features,
    ),
    // Android 2.2 (API 8)
    AndroidDistributionItem(
      platformVersion: '2.2',
      codename: 'Froyo',
      apiLevel: 8,
      cumulativeDistribution: 100.0,
      barColor: Color(0xFF4FC3F7),
      releaseDateZh: '2010年5月20日',
      releaseDateEn: 'May 20, 2010',
      summaryUrl: 'https://developer.android.com/about/versions/android-2.2-highlights',
      featureSections: kAndroid22Features,
    ),
    // Android 2.3 (API 9)
    AndroidDistributionItem(
      platformVersion: '2.3',
      codename: 'Gingerbread',
      apiLevel: 9,
      cumulativeDistribution: 100.0,
      barColor: Color(0xFF64B5F6),
      releaseDateZh: '2010年12月6日',
      releaseDateEn: 'December 6, 2010',
      summaryUrl: 'https://developer.android.com/about/versions/android-2.3-highlights',
      featureSections: kAndroid23Features,
    ),
    // Android 3.0 (API 11)
    AndroidDistributionItem(
      platformVersion: '3.0',
      codename: 'Honeycomb',
      apiLevel: 11,
      cumulativeDistribution: 100.0,
      barColor: Color(0xFF7986CB),
      releaseDateZh: '2011年2月22日',
      releaseDateEn: 'February 22, 2011',
      summaryUrl: 'https://developer.android.com/about/versions/android-3.0-highlights',
      featureSections: kAndroid30Features,
    ),
    // Android 4.0 (API 14)
    AndroidDistributionItem(
      platformVersion: '4.0',
      codename: 'Ice Cream Sandwich',
      apiLevel: 14,
      cumulativeDistribution: 100.0,
      barColor: Color(0xFF9575CD),
      releaseDateZh: '2011年10月18日',
      releaseDateEn: 'October 18, 2011',
      summaryUrl: 'https://developer.android.com/about/versions/android-4.0-highlights',
      featureSections: kAndroid40Features,
    ),
    // Android 4.1 (API 16)
    AndroidDistributionItem(
      platformVersion: '4.1',
      codename: 'Jelly Bean',
      apiLevel: 16,
      cumulativeDistribution: 100.0,
      barColor: Color(0xFFBA68C8),
      releaseDateZh: '2012年7月9日',
      releaseDateEn: 'July 9, 2012',
      summaryUrl: 'https://developer.android.com/about/versions/jelly-bean',
      featureSections: kAndroid41Features,
    ),
    // Android 4.2 (API 17)
    AndroidDistributionItem(
      platformVersion: '4.2',
      codename: 'Jelly Bean',
      apiLevel: 17,
      cumulativeDistribution: 100.0,
      barColor: Color(0xFFF06292),
      releaseDateZh: '2012年11月13日',
      releaseDateEn: 'November 13, 2012',
      summaryUrl: 'https://developer.android.com/about/versions/jelly-bean',
      featureSections: kAndroid42Features,
    ),
    // Android 4.3 (API 18)
    AndroidDistributionItem(
      platformVersion: '4.3',
      codename: 'Jelly Bean',
      apiLevel: 18,
      cumulativeDistribution: 100.0,
      barColor: Color(0xFFE57373),
      releaseDateZh: '2013年7月24日',
      releaseDateEn: 'July 24, 2013',
      summaryUrl: 'https://developer.android.com/about/versions/jelly-bean',
      featureSections: kAndroid43Features,
    ),
    // Android 4.4 (API 19)
    AndroidDistributionItem(
      platformVersion: '4.4',
      codename: 'KitKat',
      apiLevel: 19,
      cumulativeDistribution: 100.0,
      barColor: Color(0xFF795548),
      releaseDateZh: '2013年10月31日',
      releaseDateEn: 'October 31, 2013',
      summaryUrl: 'https://developer.android.com/about/versions/kitkat',
      featureSections: kAndroid44Features,
    ),
    // Android 5.0 (API 21)
    AndroidDistributionItem(
      platformVersion: '5',
      codename: 'Lollipop',
      apiLevel: 21,
      cumulativeDistribution: 100.0,
      barColor: Color(0xFFD5E0D5),
      releaseDateZh: '2014年11月12日',
      releaseDateEn: 'November 12, 2014',
      summaryUrl: 'https://developer.android.com/about/versions/android-5.0.html',
      featureSections: kAndroid50Features,
    ),
    // Android 5.1 (API 22)
    AndroidDistributionItem(
      platformVersion: '5.1',
      codename: 'Lollipop',
      apiLevel: 22,
      cumulativeDistribution: 99.9,
      barColor: Color(0xFF60B66E),
      releaseDateZh: '2015年3月9日',
      releaseDateEn: 'March 9, 2015',
      summaryUrl: 'https://developer.android.com/about/versions/android-5.1.html',
      featureSections: kAndroid51Features,
    ),
    // Android 6.0 (API 23)
    AndroidDistributionItem(
      platformVersion: '6',
      codename: 'Marshmallow',
      apiLevel: 23,
      cumulativeDistribution: 99.6,
      barColor: Color(0xFF99AAB3),
      releaseDateZh: '2015年10月5日',
      releaseDateEn: 'October 5, 2015',
      summaryUrl: 'https://developer.android.com/about/versions/marshmallow/android-6.0.html',
      featureSections: kAndroid60Features,
    ),
    // Android 7.0 (API 24)
    AndroidDistributionItem(
      platformVersion: '7',
      codename: 'Nougat',
      apiLevel: 24,
      cumulativeDistribution: 99.2,
      barColor: Color(0xFFE6AF34),
      releaseDateZh: '2016年8月22日',
      releaseDateEn: 'August 22, 2016',
      summaryUrl: 'https://developer.android.com/about/versions/nougat/android-7.0.html',
      featureSections: kAndroid70Features,
    ),
    // Android 7.1 (API 25)
    AndroidDistributionItem(
      platformVersion: '7.1',
      codename: 'Nougat',
      apiLevel: 25,
      cumulativeDistribution: 98.8,
      barColor: Color(0xFFE84D4D),
      releaseDateZh: '2016年10月4日',
      releaseDateEn: 'October 4, 2016',
      summaryUrl: 'https://developer.android.com/about/versions/nougat/android-7.1.html',
      featureSections: kAndroid71Features,
    ),
    // Android 8.0 (API 26)
    AndroidDistributionItem(
      platformVersion: '8',
      codename: 'Oreo',
      apiLevel: 26,
      cumulativeDistribution: 98.4,
      barColor: Color(0xFF40CBE0),
      releaseDateZh: '2017年8月21日',
      releaseDateEn: 'August 21, 2017',
      summaryUrl: 'https://developer.android.com/about/versions/oreo/android-8.0',
      featureSections: kAndroid80Features,
    ),
    // Android 8.1 (API 27)
    AndroidDistributionItem(
      platformVersion: '8.1',
      codename: 'Oreo',
      apiLevel: 27,
      cumulativeDistribution: 97.6,
      barColor: Color(0xFFDF7E56),
      releaseDateZh: '2017年12月5日',
      releaseDateEn: 'December 5, 2017',
      summaryUrl: 'https://developer.android.com/about/versions/oreo/android-8.1',
      featureSections: kAndroid81Features,
    ),
    // Android 9 (API 28)
    AndroidDistributionItem(
      platformVersion: '9',
      codename: 'Pie',
      apiLevel: 28,
      cumulativeDistribution: 95.3,
      barColor: Color(0xFFF47B2A),
      releaseDateZh: '2018年8月6日',
      releaseDateEn: 'August 6, 2018',
      summaryUrl: 'https://developer.android.com/about/versions/pie/android-9.0',
      featureSections: kAndroid9Features,
    ),
    // Android 10 (API 29)
    AndroidDistributionItem(
      platformVersion: '10',
      codename: 'Q',
      apiLevel: 29,
      cumulativeDistribution: 90.8,
      barColor: Color(0xFFF3A800),
      releaseDateZh: '2019年9月3日',
      releaseDateEn: 'September 3, 2019',
      summaryUrl: 'https://developer.android.com/about/versions/10',
      featureSections: kAndroid10Features,
    ),
    // Android 11 (API 30)
    AndroidDistributionItem(
      platformVersion: '11',
      codename: 'R',
      apiLevel: 30,
      cumulativeDistribution: 83.0,
      barColor: Color(0xFFC7DEB7),
      releaseDateZh: '2020年9月8日',
      releaseDateEn: 'September 8, 2020',
      summaryUrl: 'https://developer.android.com/about/versions/11',
      featureSections: kAndroid11Features,
    ),
    // Android 12 (API 31)
    AndroidDistributionItem(
      platformVersion: '12',
      codename: 'S',
      apiLevel: 31,
      cumulativeDistribution: 69.3,
      barColor: Color(0xFF5BC880),
      releaseDateZh: '2021年10月4日',
      releaseDateEn: 'October 4, 2021',
      summaryUrl: 'https://developer.android.com/about/versions/12',
      featureSections: kAndroid12Features,
    ),
    // Android 13 (API 33)
    AndroidDistributionItem(
      platformVersion: '13',
      codename: 'T',
      apiLevel: 33,
      cumulativeDistribution: 57.9,
      barColor: Color(0xFF7E9DA3),
      releaseDateZh: '2022年8月15日',
      releaseDateEn: 'August 15, 2022',
      summaryUrl: 'https://developer.android.com/about/versions/13',
      featureSections: kAndroid13Features,
    ),
    // Android 14 (API 34)
    AndroidDistributionItem(
      platformVersion: '14',
      codename: 'U',
      apiLevel: 34,
      cumulativeDistribution: 44.0,
      barColor: Color(0xFFF1B514),
      releaseDateZh: '2023年10月4日',
      releaseDateEn: 'October 4, 2023',
      summaryUrl: 'https://developer.android.com/about/versions/14',
      featureSections: kAndroid14Features,
    ),
    // Android 15 (API 35)
    AndroidDistributionItem(
      platformVersion: '15',
      codename: 'V',
      apiLevel: 35,
      cumulativeDistribution: 26.8,
      barColor: Color(0xFFF54556),
      releaseDateZh: '2024年10月15日',
      releaseDateEn: 'October 15, 2024',
      summaryUrl: 'https://developer.android.com/about/versions/15',
      featureSections: kAndroid15Features,
    ),
    // Android 16 (API 36)
    AndroidDistributionItem(
      platformVersion: '16',
      codename: 'B',
      apiLevel: 36,
      cumulativeDistribution: 7.5,
      barColor: Color(0xFF40C4FF),
      releaseDateZh: '2025年6月',
      releaseDateEn: 'June 2025',
      summaryUrl: 'https://developer.android.com/about/versions/16/summary',
      featureSections: kAndroid16Features,
    ),
    // Android 17 (API 37)
    AndroidDistributionItem(
      platformVersion: '17',
      codename: 'C',
      apiLevel: 37,
      cumulativeDistribution: 0.0,
      barColor: Color(0xFF26C6DA),
      releaseDateZh: '预计 2026 年中',
      releaseDateEn: 'Expected Q2 2026',
      summaryUrl: 'https://developer.android.com/about/versions/17',
      featureSections: kAndroid17Features,
    ),
  ];

  /// 根据版本号字符串或 API 级别查找匹配的条目，找不到时默认返回最新版本 (Android 17)
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
