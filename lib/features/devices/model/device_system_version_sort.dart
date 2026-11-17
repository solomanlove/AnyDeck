import '../../../core/providers/modules/registered_device_model.dart';

/// 按设备列表实际展示的系统名和版本数字排序，不读取 SDK 或发起设备探测。
///
/// 未知版本始终置底；已知版本比较方向由 [ascending] 决定。
/// 相同版本返回 0，在线优先和稳定 ID 兜底由调用方负责。
class DeviceSystemVersionSort {
  static int compare(
    RegisteredDevice a,
    RegisteredDevice b, {
    bool ascending = true,
  }) {
    final left = _SystemVersion.parse(a.androidVersion);
    final right = _SystemVersion.parse(b.androidVersion);
    if (left == null || right == null) {
      if (left == null && right == null) return 0;
      return left == null ? 1 : -1;
    }
    var result = left.family.compareTo(right.family);
    if (result == 0) result = _compareNumbers(left.version, right.version);
    if (result == 0) result = left.api.compareTo(right.api);
    if (result == 0) result = _compareNumbers(left.suffix, right.suffix);
    return ascending ? result : -result;
  }

  /// 点分版本补零比较，使 18 与 18.0 等价，避免字符串排序及整数溢出。
  static int _compareNumbers(List<BigInt> a, List<BigInt> b) {
    final count = a.length > b.length ? a.length : b.length;
    for (var index = 0; index < count; index++) {
      final left = index < a.length ? a[index] : BigInt.zero;
      final right = index < b.length ? b[index] : BigInt.zero;
      final result = left.compareTo(right);
      if (result != 0) return result;
    }
    return 0;
  }
}

/// 系统名前缀、点分主版本、API 和预览后缀数字的轻量比较键。
class _SystemVersion {
  _SystemVersion(this.family, this.version, this.api, this.suffix);

  final String family;
  final List<BigInt> version;
  final BigInt api;
  final List<BigInt> suffix;

  static final _apiPattern = RegExp(r'\bAPI\s*(\d+)', caseSensitive: false);
  static final _versionPattern = RegExp(r'\d+(?:\.\d+)*');
  static final _numberPattern = RegExp(r'\d+');

  static _SystemVersion? parse(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty || text == '-') return null;
    final apiMatch = _apiPattern.firstMatch(text);
    // 去掉 API 注解，避免仅有 API 的 HarmonyOS NEXT 被拆成错误的系统名。
    final release =
        (apiMatch == null ? text : text.substring(0, apiMatch.start))
            .replaceFirst(RegExp(r'[\s(]+$'), '');
    final versionMatch = _versionPattern.firstMatch(release);
    if (versionMatch == null && apiMatch == null) return null;
    final api = apiMatch == null
        ? BigInt.zero
        : BigInt.parse(apiMatch.group(1)!);
    final family =
        (versionMatch == null
                ? release
                : release.substring(0, versionMatch.start))
            .trim()
            .replaceFirst(RegExp(r'[\s_-]+$'), '')
            .toLowerCase();
    if (versionMatch == null) {
      return _SystemVersion(family, [api], BigInt.zero, []);
    }
    final version = versionMatch
        .group(0)!
        .split('.')
        .map(BigInt.parse)
        .toList();
    final suffix = _numberPattern
        .allMatches(release.substring(versionMatch.end))
        .map((match) => BigInt.parse(match.group(0)!))
        .toList();
    return _SystemVersion(family, version, api, suffix);
  }
}
