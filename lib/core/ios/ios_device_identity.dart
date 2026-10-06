import 'ios_overview_details.dart';

/// 统一设备发现和历史缓存中的 iOS 型号、版本，避免将 ProductName 当作机型。
abstract final class IosDeviceIdentity {
  /// 支持原始 ProductType 和旧版的「iPhone OS (iPhone8,1)」缓存。
  static String? modelName(String? value, {String? fallback}) {
    final model = value?.trim() ?? '';
    final productType = RegExp(
      r'(?:iPhone|iPad|iPod)\d+,\d+',
    ).firstMatch(model)?.group(0);
    if (productType != null) {
      return IosModelSpec.byProductType[productType]?.name ?? productType;
    }
    if (model.isNotEmpty) return model;
    final name = fallback?.trim();
    return name == null || name.isEmpty ? null : name;
  }

  /// 只缓存实际版本号，过滤 go-ios 缺失字段时返回的「iOS」占位值。
  static String? versionNumber(String? value) {
    final version = (value ?? '').trim().replaceFirst(
      RegExp(r'^iOS\s+', caseSensitive: false),
      '',
    );
    return RegExp(r'^\d+(?:\.\d+){0,2}$').hasMatch(version) ? version : null;
  }

  /// 系统版本列沿用公共注册表字段，统一添加一次 iOS 前缀。
  static String? versionLabel(String? value) {
    final version = versionNumber(value);
    return version == null ? null : 'iOS $version';
  }
}
