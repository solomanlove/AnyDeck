import 'dart:convert';

/// HarmonyOS 已安装应用的 `bm dump -n` 分析结果。
class HarmonyAppDetail {
  const HarmonyAppDetail({
    required this.bundleName,
    required this.versionName,
    required this.versionCode,
    required this.vendor,
    required this.organization,
    required this.compileSdkVersion,
    required this.compatibleApiVersion,
    required this.targetApiVersion,
    required this.releaseType,
    required this.provisionType,
    required this.distributionType,
    required this.cpuAbi,
    required this.codePath,
    required this.fingerprint,
    required this.enabled,
    required this.systemApp,
    required this.installTime,
    required this.updateTime,
    required this.modules,
    required this.permissions,
  });

  final String bundleName;
  final String versionName;
  final int versionCode;
  final String vendor;
  final String organization;
  final String compileSdkVersion;
  final int compatibleApiVersion;
  final int targetApiVersion;
  final String releaseType;
  final String provisionType;
  final String distributionType;
  final String cpuAbi;
  final String codePath;
  final String fingerprint;
  final bool enabled;
  final bool systemApp;
  final int installTime;
  final int updateTime;
  final List<HarmonyModuleDetail> modules;
  final List<HarmonyPermissionDetail> permissions;

  List<HarmonyComponentDetail> get abilities => [
    for (final module in modules) ...module.abilities,
  ];

  List<HarmonyComponentDetail> get extensions => [
    for (final module in modules) ...module.extensions,
  ];

  Map<String, String> get metadata => {
    for (final module in modules) ...module.metadata,
  };
}

/// 单个 HAP Module 的静态信息。
class HarmonyModuleDetail {
  const HarmonyModuleDetail({
    required this.name,
    required this.packageName,
    required this.mainElementName,
    required this.hapPath,
    required this.moduleType,
    required this.cpuAbi,
    required this.deviceTypes,
    required this.nativeLibraries,
    required this.abilities,
    required this.extensions,
    required this.metadata,
  });

  final String name;
  final String packageName;
  final String mainElementName;
  final String hapPath;
  final int moduleType;
  final String cpuAbi;
  final List<String> deviceTypes;
  final List<String> nativeLibraries;
  final List<HarmonyComponentDetail> abilities;
  final List<HarmonyComponentDetail> extensions;
  final Map<String, String> metadata;
}

/// UIAbility 或 ExtensionAbility 的公共展示信息。
class HarmonyComponentDetail {
  const HarmonyComponentDetail({
    required this.name,
    required this.moduleName,
    required this.sourceEntry,
    required this.process,
    required this.type,
    required this.enabled,
    required this.visible,
    required this.permissions,
    required this.actions,
    required this.entities,
  });

  final String name;
  final String moduleName;
  final String sourceEntry;
  final String process;
  final String type;
  final bool enabled;
  final bool visible;
  final List<String> permissions;
  final List<String> actions;
  final List<String> entities;
}

/// HarmonyOS Manifest 中声明的权限及使用场景。
class HarmonyPermissionDetail {
  const HarmonyPermissionDetail({
    required this.name,
    required this.moduleName,
    required this.reason,
    required this.abilities,
    required this.when,
  });

  final String name;
  final String moduleName;
  final String reason;
  final List<String> abilities;
  final String when;
}

/// 将 HDC 返回的 `bm dump -n` 文本解析成独立 HarmonyOS 分析模型。
class HarmonyAppDetailParser {
  const HarmonyAppDetailParser._();

  static HarmonyAppDetail parse(String output) {
    final start = output.indexOf('{');
    final end = output.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('bm dump 未返回应用 JSON');
    }

    final decoded = jsonDecode(output.substring(start, end + 1));
    if (decoded is! Map) {
      throw const FormatException('bm dump 应用 JSON 格式无效');
    }
    final root = Map<String, dynamic>.from(decoded);
    final application = _map(root['applicationInfo']);
    final bundleName = _string(
      root['name'],
      fallback: _string(application['bundleName']),
    );
    if (bundleName.isEmpty) {
      throw const FormatException('bm dump 未包含 bundleName');
    }

    final modules = <HarmonyModuleDetail>[];
    for (final rawModule in _list(root['hapModuleInfos'])) {
      final module = _map(rawModule);
      modules.add(
        HarmonyModuleDetail(
          name: _string(
            module['moduleName'],
            fallback: _string(module['name']),
          ),
          packageName: _string(module['packageName']),
          mainElementName: _string(module['mainElementName']),
          hapPath: _string(module['hapPath']),
          moduleType: _integer(module['moduleType']),
          cpuAbi: _string(module['cpuAbi']),
          deviceTypes: _strings(module['deviceTypes']),
          nativeLibraries: _strings(module['nativeLibraryFileNames']),
          abilities: _components(module['abilityInfos'], extension: false),
          extensions: _components(module['extensionInfos'], extension: true),
          metadata: _metadata(module['metadata']),
        ),
      );
    }

    final permissions = <HarmonyPermissionDetail>[];
    for (final rawPermission in _list(root['reqPermissionDetails'])) {
      final permission = _map(rawPermission);
      final usedScene = _map(permission['usedScene']);
      permissions.add(
        HarmonyPermissionDetail(
          name: _string(permission['name']),
          moduleName: _string(permission['moduleName']),
          reason: _string(permission['reason']),
          abilities: _strings(usedScene['abilities']),
          when: _string(usedScene['when']),
        ),
      );
    }

    return HarmonyAppDetail(
      bundleName: bundleName,
      versionName: _string(
        root['versionName'],
        fallback: _string(application['versionName']),
      ),
      versionCode: _integer(
        root['versionCode'],
        fallback: _integer(application['versionCode']),
      ),
      vendor: _string(root['vendor'], fallback: _string(application['vendor'])),
      organization: _string(application['organization']),
      compileSdkVersion: _string(application['compileSdkVersion']),
      compatibleApiVersion: _integer(
        root['compatibleVersion'],
        fallback: _integer(application['apiCompatibleVersion']),
      ),
      targetApiVersion: _integer(
        root['targetVersion'],
        fallback: _integer(application['apiTargetVersion']),
      ),
      releaseType: _string(root['releaseType']),
      provisionType: _string(application['appProvisionType']),
      distributionType: _string(application['appDistributionType']),
      cpuAbi: _string(application['cpuAbi']),
      codePath: _string(application['codePath']),
      fingerprint: _string(application['fingerprint']),
      enabled: application['enabled'] as bool? ?? true,
      systemApp: application['isSystemApp'] as bool? ?? false,
      installTime: _integer(root['installTime']),
      updateTime: _integer(root['updateTime']),
      modules: List.unmodifiable(modules),
      permissions: List.unmodifiable(permissions),
    );
  }

  static List<HarmonyComponentDetail> _components(
    Object? value, {
    required bool extension,
  }) {
    final components = <HarmonyComponentDetail>[];
    for (final rawComponent in _list(value)) {
      final component = _map(rawComponent);
      final actions = <String>[];
      final entities = <String>[];
      for (final rawSkill in _list(component['skills'])) {
        final skill = _map(rawSkill);
        actions.addAll(_strings(skill['actions']));
        entities.addAll(_strings(skill['entities']));
      }
      components.add(
        HarmonyComponentDetail(
          name: _string(component['name']),
          moduleName: _string(component['moduleName']),
          sourceEntry: _string(component['srcEntrance']),
          process: _string(component['process']),
          type: extension
              ? _string(
                  component['extensionTypeName'],
                  fallback: '${_integer(component['type'])}',
                )
              : '${_integer(component['type'])}',
          enabled: component['enabled'] as bool? ?? true,
          visible: component['visible'] as bool? ?? false,
          permissions: _strings(component['permissions']),
          actions: List.unmodifiable(actions.toSet()),
          entities: List.unmodifiable(entities.toSet()),
        ),
      );
    }
    return List.unmodifiable(components);
  }

  static Map<String, String> _metadata(Object? value) {
    final result = <String, String>{};
    for (final rawItem in _list(value)) {
      final item = _map(rawItem);
      final name = _string(item['name']);
      if (name.isEmpty) continue;
      result[name] = _string(
        item['value'],
        fallback: _string(item['resource']),
      );
    }
    return Map.unmodifiable(result);
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  static List<dynamic> _list(Object? value) =>
      value is List ? List<dynamic>.from(value) : const [];

  static List<String> _strings(Object? value) => _list(value)
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  static String _string(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static int _integer(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

/// 表示设备或当前系统版本无法提供 HarmonyOS 应用分析数据。
class HarmonyAppAnalysisUnsupportedException implements Exception {
  const HarmonyAppAnalysisUnsupportedException(this.message);

  final String message;

  @override
  String toString() => message;
}
