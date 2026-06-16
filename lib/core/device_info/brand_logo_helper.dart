import '../../app/theme/app_icon.dart';

class BrandLogoHelper {
  /// Maps a device's manufacturer or brand name to the corresponding asset path.
  /// Returns null if the brand is not matched, suggesting a fallback to default icon.
  static String? getBrandLogoAsset(String brandName) {
    final name = brandName.trim().toLowerCase();
    if (name.isEmpty || name == '-' || name == 'unknown') {
      return null;
    }

    // 根据品牌名称匹配并返回对应的图标资源路径
    if (name.contains('xiaomi') || name.contains('redmi')) {
      return AppIcons.xiaomi;
    }
    if (name.contains('huawei')) {
      return AppIcons.huawei;
    }
    if (name.contains('honor')) {
      return AppIcons.honor;
    }
    if (name.contains('oppo') || name.contains('realme')) {
      return AppIcons.oppo;
    }
    if (name.contains('vivo')) {
      return AppIcons.vivo;
    }
    if (name.contains('samsung')) {
      return AppIcons.samsung;
    }
    if (name.contains('oneplus')) {
      return AppIcons.oneplus;
    }
    if (name.contains('google')) {
      return AppIcons.google;
    }

    return null;
  }
}

