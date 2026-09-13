import '../../app/theme/app_icon.dart';

/// 统一解析设备图标，原始品牌和制造商字段不受展示规则影响。
class BrandLogoHelper {
  /// 优先匹配 [brandName]，无图标时使用 [manufacturer]；均未命中返回 null。
  static String? getBrandLogoAsset(String brandName, {String? manufacturer}) {
    return _matchLogoAsset(brandName) ?? _matchLogoAsset(manufacturer ?? '');
  }

  static String? _matchLogoAsset(String brandName) {
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
    if (name.contains('apple') || name.contains('iphone') || name.contains('ios')) {
      return AppIcons.apple;
    }

    return null;
  }
}

