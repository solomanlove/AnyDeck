import 'package:lpinyin/lpinyin.dart';

import '../../../core/ios/ios_app_info.dart';

/// iOS 应用页与 Android 对齐的四种分类。
enum IosAppFilter { user, system, all, favorites }

/// 名称、Bundle ID 和中文拼音筛选；不依据 com.apple 前缀猜测系统应用。
List<IosAppInfo> filterIosApps(
  List<IosAppInfo> apps, {
  required IosAppFilter category,
  required String query,
  required Set<String> favorites,
}) {
  final filter = query.trim().toLowerCase();
  final compact = filter.replaceAll(' ', '');
  return apps.where((app) {
    final included = switch (category) {
      IosAppFilter.user => !app.system,
      IosAppFilter.system => app.system,
      IosAppFilter.all => true,
      IosAppFilter.favorites => favorites.contains(app.bundleId),
    };
    if (!included) return false;
    if (filter.isEmpty ||
        app.name.toLowerCase().contains(filter) ||
        app.bundleId.toLowerCase().contains(filter)) {
      return true;
    }
    return PinyinHelper.getPinyinE(
          app.name,
          format: PinyinFormat.WITHOUT_TONE,
        ).toLowerCase().replaceAll(' ', '').contains(compact) ||
        PinyinHelper.getShortPinyin(app.name).toLowerCase().contains(compact);
  }).toList();
}

/// 中文按拼音首字母定位，数字、符号和其他文字归到 #。
String iosAppFirstLetter(IosAppInfo app) {
  final name = app.name.trim();
  if (name.isEmpty) return '#';
  final pinyin = PinyinHelper.getFirstWordPinyin(name).toUpperCase();
  final first = pinyin.isEmpty ? name[0].toUpperCase() : pinyin[0];
  return RegExp(r'^[A-Z]$').hasMatch(first) ? first : '#';
}
