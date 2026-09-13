import 'package:any_deck/app/theme/app_icon.dart';
import 'package:any_deck/core/device_info/brand_logo_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// 覆盖品牌优先、制造商兜底以及未知设备的图标边界。
void main() {
  test('Meitu uses Xiaomi manufacturer without a global Meitu alias', () {
    expect(
      BrandLogoHelper.getBrandLogoAsset('Meitu', manufacturer: 'Xiaomi'),
      AppIcons.xiaomi,
    );
    expect(
      BrandLogoHelper.getBrandLogoAsset('Meitu', manufacturer: 'Meitu'),
      isNull,
    );
  });

  test('recognized brand takes precedence over manufacturer', () {
    expect(
      BrandLogoHelper.getBrandLogoAsset('Google', manufacturer: 'Samsung'),
      AppIcons.google,
    );
    expect(BrandLogoHelper.getBrandLogoAsset('Redmi'), AppIcons.xiaomi);
    expect(BrandLogoHelper.getBrandLogoAsset('Apple'), AppIcons.apple);
    expect(BrandLogoHelper.getBrandLogoAsset('HUAWEI'), AppIcons.huawei);
  });

  test('normalizes whitespace and case for manufacturer fallback', () {
    for (final brand in ['', '-', 'unknown', 'Meitu']) {
      expect(
        BrandLogoHelper.getBrandLogoAsset(brand, manufacturer: '  XIAOMI  '),
        AppIcons.xiaomi,
      );
    }
  });

  test('unknown or missing manufacturer keeps generic device icon', () {
    for (final manufacturer in [null, '', '-', 'unknown', 'Other']) {
      expect(
        BrandLogoHelper.getBrandLogoAsset('Meitu', manufacturer: manufacturer),
        isNull,
      );
    }
  });
}
