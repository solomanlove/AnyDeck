/// Android 版本与 API 级别及代号的映射助手。
class AndroidVersionHelper {
  // 核心映射表，包含 Android 版本、API Level 以及代号 (Codename)
  static const Map<String, String> _apiMap = {
    '16': 'API 36 (Baklava)',
    '15': 'API 35 (Vanilla Ice Cream)',
    '14': 'API 34 (Upside Down Cake)',
    '13': 'API 33 (Tiramisu)',
    '12L': 'API 32 (Snow Cone v2)',
    '12': 'API 31 (Snow Cone)',
    '11': 'API 30 (Red Velvet Cake)',
    '10': 'API 29 (Quince Tart)',
    '9': 'API 28 (Pie)',
    '8.1': 'API 27 (Oreo)',
    '8.0': 'API 26 (Oreo)',
    '7.1': 'API 25 (Nougat)',
    '7.0': 'API 24 (Nougat)',
    '6.0': 'API 23 (Marshmallow)',
    '5.1': 'API 22 (Lollipop)',
    '5.0': 'API 21 (Lollipop)',
    '4.4': 'API 19 (KitKat)',
  };

  /// 生成等宽对齐的 Tooltip 文本。
  static String getApiMappingTooltip(String title) {
    final sb = StringBuffer();
    sb.writeln(title);
    sb.writeln('-----------------------------------');
    _apiMap.forEach((version, apiInfo) {
      // 动态计算间距，保持等宽字体下的箭头对齐
      final padding = version.length == 2
          ? '  '
          : version.length == 3
              ? ' '
              : '';
      sb.writeln('Android $version$padding ➔  $apiInfo');
    });
    return sb.toString();
  }
}
