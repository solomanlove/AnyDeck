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

  // 旧版本及当前映射表尚未收录的版本；主映射表同时服务于概览页 Tooltip。
  static const Map<int, String> _additionalVersionsByApi = {
    1: '1.0',
    2: '1.1',
    3: '1.5',
    4: '1.6',
    5: '2.0',
    6: '2.0.1',
    7: '2.1',
    8: '2.2',
    9: '2.3',
    10: '2.3.3',
    11: '3.0',
    12: '3.1',
    13: '3.2',
    14: '4.0',
    15: '4.0.3',
    16: '4.1',
    17: '4.2',
    18: '4.3',
    20: '4.4W',
    37: '17',
  };

  /// 将应用 Manifest 的 API level 转成 Android 版本；未知级别只显示 API，避免误报版本。
  static String formatApiLevel(int? apiLevel) {
    if (apiLevel == null) return '-';
    var version = _additionalVersionsByApi[apiLevel];
    if (version == null) {
      for (final entry in _apiMap.entries) {
        if (entry.value.startsWith('API $apiLevel (')) {
          version = entry.key;
          break;
        }
      }
    }
    return version == null
        ? 'API $apiLevel'
        : 'Android $version (API $apiLevel)';
  }

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

  /// 解析 Android getprop 的 `[key]: [value]` 输出。
  static Map<String, String> parseGetProp(String output) {
    final properties = <String, String>{};
    final pattern = RegExp(r'^\[(.+?)\]: \[(.*)\]$');
    for (final line in output.split('\n')) {
      final match = pattern.firstMatch(line.trim());
      if (match != null) {
        properties[match.group(1)!] = match.group(2)!;
      }
    }
    return properties;
  }

  /// 根据 getprop 属性检测厂商系统及其版本，未命中时交由 UI 展示统一兜底文案。
  static String? getCustomOsVersion(Map<String, String> properties) {
    final harmonyVersion = _firstNonEmpty(properties, [
      'ro.huawei.build.version.harmony',
      'hw_sc.build.platform.version',
    ]);
    if (harmonyVersion != null) {
      return _withName('HarmonyOS', harmonyVersion);
    }

    final magicVersion = _firstNonEmpty(properties, [
      'ro.honor.build.version.magic',
      'ro.build.version.magic',
    ]);
    if (magicVersion != null) {
      return _withName('MagicOS', magicVersion);
    }

    final emuiVersion = _firstNonEmpty(properties, ['ro.build.version.emui']);
    if (emuiVersion != null) {
      return _withName(
        'EMUI',
        emuiVersion.replaceFirst(
          RegExp(r'^EmotionUI_', caseSensitive: false),
          '',
        ),
      );
    }

    final hyperOsVersion = _firstNonEmpty(properties, [
      'ro.mi.os.version.name',
    ]);
    if (hyperOsVersion != null) {
      return _withName('HyperOS', hyperOsVersion);
    }
    final miuiVersion = _firstNonEmpty(properties, ['ro.miui.ui.version.name']);
    if (miuiVersion != null) {
      return _withName('MIUI', miuiVersion);
    }

    final oxygenOsVersion = _firstNonEmpty(properties, [
      'ro.oxygen.version',
      'ro.oxygen.version.display',
    ]);
    if (oxygenOsVersion != null) {
      return _withName('OxygenOS', oxygenOsVersion);
    }
    final realmeUiVersion = _firstNonEmpty(properties, [
      'ro.build.version.realmeui',
    ]);
    if (realmeUiVersion != null) {
      return _withName('realme UI', realmeUiVersion);
    }
    final colorOsVersion = _firstNonEmpty(properties, [
      'ro.build.version.opporom',
      'ro.build.version.coloros',
      'ro.rom.different.version',
    ]);
    if (colorOsVersion != null) {
      return _withName('ColorOS', colorOsVersion);
    }

    final vivoOsName = _firstNonEmpty(properties, ['ro.vivo.os.name']);
    final vivoOsVersion = _firstNonEmpty(properties, ['ro.vivo.os.version']);
    if (vivoOsName != null) {
      return vivoOsVersion == null
          ? vivoOsName
          : _withName(vivoOsName, vivoOsVersion);
    }
    if (vivoOsVersion != null) {
      return _withName('OriginOS/Funtouch OS', vivoOsVersion);
    }

    final displayId = _firstNonEmpty(properties, ['ro.build.display.id']);
    if (displayId != null && displayId.toLowerCase().contains('flyme')) {
      return displayId;
    }

    return null;
  }

  static String? _firstNonEmpty(
    Map<String, String> properties,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = properties[key]?.trim();
      if (value != null &&
          value.isNotEmpty &&
          value.toLowerCase() != 'unknown') {
        return value;
      }
    }
    return null;
  }

  static String _withName(String name, String version) {
    final cleanVersion = version.trim();
    if (cleanVersion.toLowerCase().startsWith(name.toLowerCase())) {
      return cleanVersion;
    }
    return '$name $cleanVersion';
  }
}
