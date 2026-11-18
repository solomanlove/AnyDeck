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
    // 刷机后的系统身份优先于可能残留在 vendor 分区中的原厂属性。
    final lineageVersion = _firstNonEmpty(properties, [
      'ro.lineage.build.version',
      'ro.lineage.version',
    ]);
    if (lineageVersion != null) {
      return _withName('LineageOS', lineageVersion);
    }

    final harmonyVersion = _firstNonEmpty(properties, [
      'ro.huawei.build.version.harmony',
      'hw_sc.build.platform.version',
    ]);
    if (harmonyVersion != null) {
      return _withName('HarmonyOS', harmonyVersion);
    }
    if (_firstNonEmpty(properties, ['ro.build.ohos.devicetype']) != null) {
      return 'HarmonyOS';
    }

    final magicVersion = _firstNonEmpty(properties, [
      'ro.honor.build.version.magic',
      'ro.build.version.magic',
    ]);
    if (magicVersion != null) {
      return _namedOsVersion(magicVersion, ['MagicUI', 'MagicOS']) ??
          _withName('MagicOS', magicVersion);
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

    final hyperOsBuild = _firstNonEmpty(properties, [
      'ro.mi.os.version.incremental',
    ]);
    final hyperOsVersion =
        hyperOsBuild != null &&
            RegExp(r'^OS\d', caseSensitive: false).hasMatch(hyperOsBuild)
        ? hyperOsBuild
        : _firstNonEmpty(properties, ['ro.mi.os.version.name']);
    if (hyperOsVersion != null) {
      return _withName('HyperOS', hyperOsVersion);
    }

    // JOYUI 同时携带 MIUI 兼容属性，仅以增量版本的明确后缀区分。
    final incremental = _firstNonEmpty(properties, [
      'ro.build.version.incremental',
    ]);
    final joyUiVersion = RegExp(
      r'^V?(\d+(?:\.\d+)*)\.JOYUI$',
      caseSensitive: false,
    ).firstMatch(incremental ?? '');
    if (joyUiVersion != null) {
      return _withName('JOYUI', joyUiVersion.group(1)!);
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
    final onePlusRom = _firstNonEmpty(properties, ['ro.rom.version']);
    final namedOnePlusRom = _namedOsVersion(
      onePlusRom?.replaceFirst(
        RegExp(r'^Oxygen\s+OS', caseSensitive: false),
        'OxygenOS',
      ),
      ['OxygenOS', 'HydrogenOS', 'H2OS'],
    );
    if (namedOnePlusRom != null) return namedOnePlusRom;

    final realmeUiVersion = _firstNonEmpty(properties, [
      'ro.build.version.realmeui',
    ]);
    if (realmeUiVersion != null) {
      return _withName('realme UI', realmeUiVersion);
    }
    final colorOsVersion = _firstNonEmpty(properties, [
      'ro.build.version.oplusrom.display',
      'ro.build.version.oplusrom',
      'ro.build.version.opporom',
      'ro.build.version.coloros',
      'ro.rom.different.version',
    ]);
    if (colorOsVersion != null) {
      final namedOplusRom = _namedOsVersion(colorOsVersion, [
        'OxygenOS',
        'ColorOS',
        'realme UI',
      ]);
      if (namedOplusRom != null) return namedOplusRom;
      final stockType = _firstNonEmpty(properties, [
        'ro.oplus.image.my_stock.type',
      ])?.toLowerCase();
      // Oplus 为多个系统共用；只对有明确国际版身份的 OnePlus 使用 OxygenOS。
      if (stockType == 'export_oneplus' || stockType == 'gdpr_oneplus') {
        return _withName('OxygenOS', colorOsVersion);
      }
      final brands = [
        'ro.product.brand',
        'ro.product.vendor.brand',
        'ro.product.manufacturer',
        'ro.product.vendor.manufacturer',
      ].map((key) => properties[key]?.trim().toLowerCase());
      final legacyColorOs = _firstNonEmpty(properties, [
        'ro.build.version.opporom',
        'ro.build.version.coloros',
      ]);
      // 保留旧的明确 ColorOS 属性回退；新共享属性不足以确定一加/realme 身份。
      if (legacyColorOs != null ||
          !brands.any((brand) => brand == 'oneplus' || brand == 'realme')) {
        return _withName('ColorOS', colorOsVersion);
      }
    }

    // 展示属性包含真实系统名称，旧 name/version 可能仍返回 Funtouch 兼容值。
    final vivoDisplay = _namedOsVersion(
      _firstNonEmpty(properties, ['ro.vivo.os.build.display.id']),
      ['OriginOS', 'Funtouch OS', 'Funtouch'],
    );
    if (vivoDisplay != null) return vivoDisplay;
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
    final flymeDisplay = _namedOsVersion(displayId, ['Flyme OS', 'Flyme']);
    if (flymeDisplay != null) return flymeDisplay;
    final flymeVersion = _namedOsVersion(
      _firstNonEmpty(properties, ['ro.flyme.version.id']),
      ['Flyme OS', 'Flyme'],
    );
    if (flymeVersion != null) return flymeVersion;

    final oneUiVersion = _firstNonEmpty(properties, ['ro.build.version.oneui']);
    final encodedOneUi = int.tryParse(oneUiVersion ?? '', radix: 10);
    if (encodedOneUi != null && encodedOneUi >= 10000) {
      // 三星将 One UI 编码为 major * 10000 + minor * 100 + patch。
      // 保留主次版本，仅在补丁号非零时展示第三段；不根据品牌或 Android 版本推测。
      final major = encodedOneUi ~/ 10000;
      final minor = (encodedOneUi ~/ 100) % 100;
      final patch = encodedOneUi % 100;
      return patch == 0
          ? 'One UI $major.$minor'
          : 'One UI $major.$minor.$patch';
    }

    // 新系统沿用旧兼容属性时，优先读取 display.id 中明确的名称与版本。
    final namedDisplay = _namedOsVersion(displayId, [
      'MyOS',
      'RedMagicOS',
      'NebulaAIOS',
    ]);
    if (namedDisplay != null) return namedDisplay;
    final zuiDisplay = RegExp(
      r'(?:^|_)(ZUXOS|ZUI)_([0-9]+(?:\.[0-9A-Za-z]+)*)(?:_|$)',
      caseSensitive: false,
    ).firstMatch(displayId ?? '');
    if (zuiDisplay != null) {
      return _withName(
        zuiDisplay.group(1)!.toUpperCase(),
        zuiDisplay.group(2)!,
      );
    }
    final zuiVersion = _firstNonEmpty(properties, ['ro.com.zui.version']);
    if (zuiVersion != null) return _withName('ZUI', zuiVersion);

    final nubiaName = _firstNonEmpty(properties, ['ro.build.nubia.rom.name']);
    final nubiaVersion = _firstNonEmpty(properties, [
      'ro.build.nubia.rom.code',
    ]);
    if (nubiaName != null) {
      return nubiaVersion == null
          ? nubiaName
          : _withName(nubiaName, nubiaVersion);
    }
    final miFavorVersion = _firstNonEmpty(properties, [
      'ro.build.MiFavor_version',
    ]);
    if (miFavorVersion != null) return _withName('MiFavor', miFavorVersion);

    final transsionVersion = _namedOsVersion(
      _firstNonEmpty(properties, ['ro.tranos.version']),
      ['HiOS', 'XOS'],
    );
    if (transsionVersion != null) return transsionVersion;

    final smartisanVersion = _firstNonEmpty(properties, [
      'ro.smartisan.version',
    ]);
    if (smartisanVersion != null) {
      return _withName(
        'SmartisanOS',
        smartisanVersion.split(RegExp(r'[-_]')).first,
      );
    }

    return null;
  }

  /// 仅解析明确系统名前缀后的版本，不把通用 Android Build ID 当作 ROM。
  static String? _namedOsVersion(String? value, List<String> names) {
    if (value == null) return null;
    for (final name in names) {
      if (value.toLowerCase() == name.toLowerCase()) return name;
      final match = RegExp(
        '^${RegExp.escape(name)}[ _]*([vV]?[0-9][0-9A-Za-z.]*)'
        r'(?=$|[ _(-])',
        caseSensitive: false,
      ).firstMatch(value);
      if (match != null) return _withName(name, match.group(1)!);
    }
    return null;
  }

  /// 获取设备代号。对于小米/红米/POCO 设备，通过 `ro.product.name` 获取机型代号。
  static String? getDeviceCodename(Map<String, String> properties) {
    final brand = _firstNonEmpty(properties, [
      'ro.product.brand',
      'ro.product.vendor.brand',
      'ro.product.manufacturer',
      'ro.product.vendor.manufacturer',
    ])?.toLowerCase() ?? '';

    final isXiaomi = brand.contains('xiaomi') ||
        brand.contains('redmi') ||
        brand.contains('poco') ||
        properties.containsKey('ro.miui.ui.version.name') ||
        properties.containsKey('ro.mi.os.version.name');

    if (isXiaomi) {
      return _firstNonEmpty(properties, [
        'ro.product.name',
        'ro.product.device',
        'ro.product.vendor.device',
      ]);
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
