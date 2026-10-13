import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/features/overview/model/android_version_distribution_data.dart';

void main() {
  group('AndroidVersionDistributionData Tests', () {
    test('包含 Android 17 以及 Android 4.4 及以下完整版本', () {
      final items = AndroidVersionDistributionData.items;

      // 验证包含 Android 17
      final hasAndroid17 = items.any((i) => i.platformVersion == '17' && i.apiLevel == 37);
      expect(hasAndroid17, isTrue);

      // 验证包含 Android 4.4
      final hasAndroid44 = items.any((i) => i.platformVersion == '4.4' && i.apiLevel == 19);
      expect(hasAndroid44, isTrue);

      // 验证包含 4.4 以下核心历史版本 (4.3, 4.2, 4.1, 4.0, 3.0, 2.3, 2.2, 2.0, 1.6, 1.5, 1.0)
      final legacyVersions = ['4.3', '4.2', '4.1', '4.0', '3.0', '2.3', '2.2', '2.0', '1.6', '1.5', '1.0'];
      for (final version in legacyVersions) {
        final exists = items.any((i) => i.platformVersion == version);
        expect(exists, isTrue, reason: '必须包含 Android $version');
      }
    });

    test('各个版本均配置了稳定版上线时间', () {
      for (final item in AndroidVersionDistributionData.items) {
        expect(item.releaseDateZh.isNotEmpty, isTrue,
            reason: 'Android ${item.platformVersion} (API ${item.apiLevel}) 必须具备中文稳定版上线时间');
        expect(item.releaseDateEn.isNotEmpty, isTrue,
            reason: 'Android ${item.platformVersion} (API ${item.apiLevel}) 必须具备英文稳定版上线时间');
        expect(item.localizedReleaseDate('zh'), equals(item.releaseDateZh));
        expect(item.localizedReleaseDate('en'), equals(item.releaseDateEn));
      }
    });

    test('各个版本均包含对开发的影响 (Developer Impact) 分类', () {
      for (final item in AndroidVersionDistributionData.items) {
        final hasImpactSection = item.featureSections.any((s) =>
            s.title.toLowerCase().contains('developer impact') ||
            (s.titleZh != null && s.titleZh!.contains('开发影响')));
        expect(hasImpactSection, isTrue,
            reason: 'Android ${item.platformVersion} (API ${item.apiLevel}) 必须包含开发影响与适配要求分类');
      }
    });

    test('Android 15 明确包含 EdgeToEdge 适配和 16KB 页面内存对齐要求', () {
      final android15 = AndroidVersionDistributionData.findItem('15');
      expect(android15.apiLevel, equals(35));

      final impactSection = android15.featureSections.firstWhere(
        (s) => s.title.toLowerCase().contains('developer impact'),
      );

      final itemsZh = impactSection.itemsZh!;
      final hasEdgeToEdge = itemsZh.any((item) => item.contains('EdgeToEdge') || item.contains('边到边'));
      final has16KB = itemsZh.any((item) => item.contains('16KB') || item.contains('16 KB'));

      expect(hasEdgeToEdge, isTrue, reason: 'Android 15 开发影响中必须包含 EdgeToEdge 适配');
      expect(has16KB, isTrue, reason: 'Android 15 开发影响中必须包含 16KB 页面内存');
    });

    test('findItem 方法查找版本正常，默认返回最新 Android 17', () {
      expect(AndroidVersionDistributionData.findItem('17').apiLevel, equals(37));
      expect(AndroidVersionDistributionData.findItem('37').platformVersion, equals('17'));
      expect(AndroidVersionDistributionData.findItem('4.4').apiLevel, equals(19));
      expect(AndroidVersionDistributionData.findItem('1.0').apiLevel, equals(1));
      expect(AndroidVersionDistributionData.findItem(null).platformVersion, equals('17'));
      expect(AndroidVersionDistributionData.findItem('invalid_version').platformVersion, equals('17'));
    });

    test('localizedLastUpdatedDate 自动获取今天日期并正确本地化', () {
      final now = DateTime.now();
      expect(AndroidVersionDistributionData.localizedLastUpdatedDate('zh'),
          contains('${now.year}年${now.month}月${now.day}日'));

      final testDate = DateTime(2026, 10, 13);
      expect(AndroidVersionDistributionData.localizedLastUpdatedDate('zh', testDate),
          equals('2026年10月13日'));
      expect(AndroidVersionDistributionData.localizedLastUpdatedDate('en', testDate),
          equals('October 13, 2026'));
    });
  });
}
