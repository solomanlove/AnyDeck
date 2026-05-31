/// 屏幕密度、比例与限定符对应关系的辅助类。
class ScreenDensityHelper {
  // 核心限定符映射表，包含 DPI、限定符、缩放倍率
  static const List<Map<String, String>> _densityBuckets = [
    {'dpi': '120 dpi', 'scale': '0.75x', 'qualifier': 'ldpi'},
    {'dpi': '160 dpi', 'scale': '1.0x',  'qualifier': 'mdpi (Baseline)'},
    {'dpi': '240 dpi', 'scale': '1.5x',  'qualifier': 'hdpi'},
    {'dpi': '320 dpi', 'scale': '2.0x',  'qualifier': 'xhdpi'},
    {'dpi': '480 dpi', 'scale': '3.0x',  'qualifier': 'xxhdpi'},
    {'dpi': '640 dpi', 'scale': '4.0x',  'qualifier': 'xxxhdpi'},
  ];

  /// 生成等宽对齐的 Tooltip 文本。
  static String getDensityMappingTooltip(String title) {
    final sb = StringBuffer();
    sb.writeln(title);
    sb.writeln('-----------------------------------');
    for (final bucket in _densityBuckets) {
      final dpi = bucket['dpi']!.padRight(7);
      final scale = bucket['scale']!.padRight(5);
      final qualifier = bucket['qualifier']!;
      sb.writeln('$dpi ➔  $scale  ($qualifier)');
    }
    return sb.toString();
  }
}
