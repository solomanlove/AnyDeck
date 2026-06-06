class BrandLogoHelper {
  /// Maps a device's manufacturer or brand name to the corresponding asset path.
  /// Returns null if the brand is not matched, suggesting a fallback to default icon.
  static String? getBrandLogoAsset(String brandName) {
    final name = brandName.trim().toLowerCase();
    if (name.isEmpty || name == '-' || name == 'unknown') {
      return null;
    }

    if (name.contains('xiaomi') || name.contains('redmi')) {
      return 'assets/brand/xiaomi_logo2.png';
    }
    if (name.contains('huawei')) {
      return 'assets/brand/huawei_logo.png';
    }
    if (name.contains('honor')) {
      return 'assets/brand/honor_logo.png';
    }
    if (name.contains('oppo') || name.contains('realme')) {
      return 'assets/brand/oppo_logo.png';
    }
    if (name.contains('vivo')) {
      return 'assets/brand/vivo_logo.png';
    }
    if (name.contains('samsung')) {
      return 'assets/brand/samsung_logo.png';
    }
    if (name.contains('oneplus')) {
      return 'assets/brand/oneplus_logo.png';
    }
    if (name.contains('google')) {
      return 'assets/brand/google_logo.png';
    }

    return null;
  }
}
