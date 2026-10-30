/// Android 屏幕分辨率、密度与刷新率的只读解析，供概览与双屏信息复用。
class AndroidDisplayParser {
  /// 概览统一按“高 x 宽”展示；原始分辨率仍保留设备返回的“宽 x 高”顺序。
  static String formatResolution(String size, {String density = '-'}) {
    if (size == '-') {
      return '-';
    }
    final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(size);
    final displaySize = match == null
        ? size
        : '${match.group(2)}x${match.group(1)}';
    return density == '-' ? displaySize : '$displaySize (${density}dpi)';
  }

  /// 计算屏幕逻辑密度并返回 qualifier (如: 3.25x (xxxhdpi))。
  static String densityQualifier(String densityStr) {
    final dpi = int.tryParse(densityStr);
    if (dpi == null) return '-';

    final scale = dpi / 160.0;
    final scaleStr = scale == scale.roundToDouble()
        ? scale.toStringAsFixed(0)
        : scale
              .toStringAsFixed(2)
              .replaceAll(RegExp(r'0+$'), '')
              .replaceAll(RegExp(r'\.$'), '');

    String qualifier;
    if (dpi <= 120) {
      qualifier = 'ldpi';
    } else if (dpi <= 160) {
      qualifier = 'mdpi';
    } else if (dpi <= 240) {
      qualifier = 'hdpi';
    } else if (dpi <= 320) {
      qualifier = 'xhdpi';
    } else if (dpi <= 480) {
      qualifier = 'xxhdpi';
    } else {
      qualifier = 'xxxhdpi';
    }

    return '${scaleStr}x ($qualifier)';
  }

  /// 从 dumpsys display 输出中解析屏幕刷新率。
  static String refreshRate(String output) {
    // 1. 尝试匹配 supportedRefreshRates [...] 或 mSupportedRefreshRates=[...]
    final ratesMatch = RegExp(
      r'(?:mSupportedRefreshRates|supportedRefreshRates)[=\s]*\[([^\]]+)\]',
    ).firstMatch(output);

    if (ratesMatch != null) {
      final listStr = ratesMatch.group(1)!;
      final rates = listStr
          .split(',')
          .map((s) => double.tryParse(s.trim()))
          .whereType<double>()
          .map((r) => r.round())
          .toSet()
          .toList();
      if (rates.isNotEmpty) {
        rates.sort();
        final maxRate = rates.last;
        return '$maxRate Hz';
      }
    }

    // 2. 尝试匹配 renderFrameRate
    final renderFrameRateMatch = RegExp(
      r'renderFrameRate\s+([0-9.]+)',
    ).firstMatch(output);
    if (renderFrameRateMatch != null) {
      final rate = double.tryParse(renderFrameRateMatch.group(1)!);
      if (rate != null) {
        return '${rate.round()} Hz';
      }
    }

    // 3. 回退匹配 supportedModes 中首个 fps=
    final fpsMatch = RegExp(r'fps=([0-9.]+)').firstMatch(output);
    if (fpsMatch != null) {
      final fps = double.tryParse(fpsMatch.group(1)!);
      if (fps != null) {
        return '${fps.round()} Hz';
      }
    }

    return '-';
  }
}
