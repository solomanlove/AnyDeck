import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../adb/adb_device.dart';
import '../../harmony/hdc_service.dart';

/// 设备注册表本地存储所维护的完整元数据聚合实体。
class DeviceRegistryPrefsData {
  DeviceRegistryPrefsData({
    required this.historyIds,
    required this.aliases,
    required this.models,
    required this.products,
    required this.ipAddresses,
    required this.androidVersions,
    required this.sdkVersions,
    required this.remarks,
    required this.tags,
    required this.serialMap,
  });

  final List<String> historyIds;
  final Map<String, String> aliases;
  final Map<String, String> models;
  final Map<String, String> products;
  final Map<String, String> ipAddresses;
  final Map<String, String> androidVersions;
  final Map<String, int> sdkVersions;
  final Map<String, String> remarks;
  final Map<String, List<String>> tags;
  final Map<String, String> serialMap;
}

/// 设备注册表持久化与历史脏数据清洗存储服务。
///
/// 负责 SharedPreferences 的读写、历史因 ADB track-devices 协议解析产生的十六进制包头清洗、
/// iOS 截断 8 位 UDID 恢复合并以及鸿蒙占位型号过滤。
class DeviceRegistryStorage {
  static const _historyKey = 'devices.history';
  static const _aliasesKey = 'devices.aliases';
  static const _modelsKey = 'devices.models';
  static const _productsKey = 'devices.products';
  static const _ipsKey = 'devices.ips';
  static const _androidVersionsKey = 'devices.androidVersions';
  static const _sdkVersionsKey = 'devices.sdkVersions';
  static const _remarksKey = 'devices.remarks';
  static const _tagsKey = 'devices.tags';

  static bool isNetworkId(String id) {
    return id.contains(':') || id.contains('.') || id == '127.0.0.1';
  }

  static String getFallbackSerial(String id) {
    if (id.startsWith('adb-') && id.contains('._adb-tls-connect')) {
      final namePart = id.substring(4, id.indexOf('._adb-tls-connect'));
      if (namePart.contains('-')) {
        final lastIndex = namePart.lastIndexOf('-');
        return namePart.substring(0, lastIndex);
      }
      return namePart;
    }
    return id;
  }

  static int? parseSdkVersion(String androidVersion) {
    final match = RegExp(r'API\s+(\d+)').firstMatch(androidVersion);
    return match == null ? null : int.tryParse(match.group(1) ?? '');
  }

  static bool isGenericHarmonyModel(String? s) =>
      HdcServiceDeviceInfo.isGenericOrInvalidModel(s);

  /// 从本地持久化存储中读取并清洗全部设备元数据。
  Future<DeviceRegistryPrefsData> loadFromPrefs(List<AdbDevice> activeDevices) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? [];
    
    final aliasesJson = prefs.getString(_aliasesKey);
    Map<String, String> aliases = {};
    if (aliasesJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(aliasesJson));
        aliases = decoded.map((key, value) => MapEntry(key, value.toString()));
      } catch (_) {}
    }

    final modelsJson = prefs.getString(_modelsKey);
    Map<String, String> models = {};
    if (modelsJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(modelsJson));
        models = decoded.map((key, value) => MapEntry(key, value.toString()))
          ..removeWhere((_, value) => value.toLowerCase().contains('fail'));
      } catch (_) {}
    }

    final productsJson = prefs.getString(_productsKey);
    Map<String, String> products = {};
    if (productsJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(productsJson));
        products = decoded.map((key, value) => MapEntry(key, value.toString()));
      } catch (_) {}
    }

    final ipsJson = prefs.getString(_ipsKey);
    Map<String, String> ips = {};
    if (ipsJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(ipsJson));
        ips = decoded.map((key, value) => MapEntry(key, value.toString()));
      } catch (_) {}
    }

    final androidVersionsJson = prefs.getString(_androidVersionsKey);
    Map<String, String> androidVersions = {};
    if (androidVersionsJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(
          jsonDecode(androidVersionsJson),
        );
        androidVersions = decoded.map(
          (key, value) => MapEntry(key, value.toString()),
        );
      } catch (_) {}
    }

    final sdkVersionsJson = prefs.getString(_sdkVersionsKey);
    Map<String, int> sdkVersions = {};
    if (sdkVersionsJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(sdkVersionsJson));
        sdkVersions = decoded.map(
          (key, value) => MapEntry(key, int.tryParse(value.toString()) ?? 0),
        )..removeWhere((_, value) => value <= 0);
      } catch (_) {}
    }

    final remarksJson = prefs.getString(_remarksKey);
    Map<String, String> remarks = {};
    if (remarksJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(remarksJson));
        remarks = decoded.map((key, value) => MapEntry(key, value.toString()));
      } catch (_) {}
    }

    final tagsJson = prefs.getString(_tagsKey);
    Map<String, List<String>> tags = {};
    if (tagsJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(tagsJson));
        tags = decoded.map((key, value) => MapEntry(key, List<String>.from(value)));
      } catch (_) {}
    }

    // 清洗因历史 ADB track-devices 协议解析漏洞产生的被十六进制长度前缀污染的脏设备 ID
    String stripHexPrefix(String rawId) {
      // iOS UDID（40 位纯十六进制或 25 位带中划线）绝不能被误判为十六进制长度前缀剥离
      if (rawId.length == 40 && !rawId.contains(RegExp(r'[^a-fA-F0-9]'))) {
        return rawId;
      }
      if (rawId.length == 25 && rawId.indexOf('-') == 8) {
        return rawId;
      }

      var current = rawId;
      while (current.length > 8) {
        final prefix = current.substring(0, 4);
        if (int.tryParse(prefix, radix: 16) != null) {
          final candidate = current.substring(4);
          if (history.contains(candidate) ||
              activeDevices.any((d) => d.id == candidate) ||
              candidate.startsWith('adb-')) {
            current = candidate;
            continue;
          }
        }
        break;
      }
      return current;
    }

    final cleanedHistory = <String>[];
    bool historyPolluted = false;
    for (final id in history) {
      final realId = stripHexPrefix(id);
      if (realId != id) {
        historyPolluted = true;
        // 将脏 ID 上的缓存元数据迁移给真实 realId
        if (aliases.containsKey(id) && !aliases.containsKey(realId)) {
          aliases[realId] = aliases[id]!;
        }
        if (models.containsKey(id) && !models.containsKey(realId)) {
          models[realId] = models[id]!;
        }
        if (products.containsKey(id) && !products.containsKey(realId)) {
          products[realId] = products[id]!;
        }
        if (ips.containsKey(id) && !ips.containsKey(realId)) {
          ips[realId] = ips[id]!;
        }
        if (androidVersions.containsKey(id) && !androidVersions.containsKey(realId)) {
          androidVersions[realId] = androidVersions[id]!;
        }
        if (sdkVersions.containsKey(id) && !sdkVersions.containsKey(realId)) {
          sdkVersions[realId] = sdkVersions[id]!;
        }
        if (remarks.containsKey(id) && !remarks.containsKey(realId)) {
          remarks[realId] = remarks[id]!;
        }
        if (tags.containsKey(id) && !tags.containsKey(realId)) {
          tags[realId] = tags[id]!;
        }

        aliases.remove(id);
        models.remove(id);
        products.remove(id);
        ips.remove(id);
        androidVersions.remove(id);
        sdkVersions.remove(id);
        remarks.remove(id);
        tags.remove(id);

        if (!cleanedHistory.contains(realId)) {
          cleanedHistory.add(realId);
        }
      } else {
        if (!cleanedHistory.contains(id)) {
          cleanedHistory.add(id);
        }
      }
    }

    // 自动清理与合并此前被历史 stripHexPrefix 截断为 8 位的残缺 iOS 设备记录，合并回完整 UDID
    final candidateFullUdids = <String>{
      ...activeDevices.map((d) => d.id),
      ...tags.keys,
      ...remarks.keys,
      ...history,
    };
    for (final fullUdid in candidateFullUdids) {
      if (fullUdid.length == 40 && !fullUdid.contains(RegExp(r'[^a-fA-F0-9]'))) {
        final suffix = fullUdid.substring(32);
        if (cleanedHistory.contains(suffix) || history.contains(suffix)) {
          historyPolluted = true;
          cleanedHistory.remove(suffix);
          history.remove(suffix);

          if (remarks.containsKey(suffix) && !remarks.containsKey(fullUdid)) {
            remarks[fullUdid] = remarks[suffix]!;
          }
          if (aliases.containsKey(suffix) && !aliases.containsKey(fullUdid)) {
            aliases[fullUdid] = aliases[suffix]!;
          }
          if (tags.containsKey(suffix) && !tags.containsKey(fullUdid)) {
            tags[fullUdid] = tags[suffix]!;
          }

          remarks.remove(suffix);
          aliases.remove(suffix);
          tags.remove(suffix);
          models.remove(suffix);
          products.remove(suffix);
        }
      }
    }

    // 自动清洗此前被异常管道输出（如 Please wait for several seconds...）污染的型号缓存
    final pollutedModelKeys = models.entries
        .where((e) => isGenericHarmonyModel(e.value))
        .map((e) => e.key)
        .toList();
    if (pollutedModelKeys.isNotEmpty) {
      for (final k in pollutedModelKeys) {
        models.remove(k);
      }
      historyPolluted = true;
    }

    if (historyPolluted) {
      history.clear();
      history.addAll(cleanedHistory);
      await prefs.setStringList(_historyKey, cleanedHistory);
      await prefs.setString(_remarksKey, jsonEncode(remarks));
      await prefs.setString(_tagsKey, jsonEncode(tags));
      await prefs.setString(_modelsKey, jsonEncode(models));
      await prefs.setString(_productsKey, jsonEncode(products));
    }

    // 加载缓存的序列号映射
    final allIds = {...history, ...activeDevices.map((d) => d.id)};
    final serialMap = <String, String>{};
    for (final id in allIds) {
      final jsonStr = prefs.getString('devices.overview.$id');
      if (jsonStr != null) {
        try {
          final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
          final cachedVersion = decoded['androidVersion']?.toString();
          if (cachedVersion != null &&
              cachedVersion.isNotEmpty &&
              cachedVersion != '-') {
            androidVersions[id] = cachedVersion;
            final cachedSdk = parseSdkVersion(cachedVersion);
            if (cachedSdk != null) {
              sdkVersions[id] = cachedSdk;
            }
          }
          final cachedIp = decoded['ipAddress']?.toString();
          if (cachedIp != null && cachedIp.isNotEmpty && cachedIp != '-') {
            ips[id] ??= cachedIp;
          }
          final cachedName = decoded['name']?.toString();
          final cachedModel = decoded['model']?.toString();
          final realName = (cachedName != null && !isGenericHarmonyModel(cachedName))
              ? cachedName
              : ((cachedModel != null && !isGenericHarmonyModel(cachedModel))
                  ? cachedModel
                  : null);
          if (realName != null) {
            if (models[id] == null || isGenericHarmonyModel(models[id])) {
              models[id] = realName;
            }
          }
        } catch (_) {}
      }

      if (!isNetworkId(id)) {
        serialMap[id] = id;
      } else {
        var serial = getFallbackSerial(id);
        if (serial != id) {
          serialMap[id] = serial;
        }

        if (jsonStr != null) {
          try {
            final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
            final cachedSerial = decoded['serial']?.toString();
            if (cachedSerial != null &&
                cachedSerial.isNotEmpty &&
                cachedSerial != '-') {
              serialMap[id] = cachedSerial;
              final cachedVersion = androidVersions[id];
              if (cachedVersion != null && cachedVersion.isNotEmpty) {
                androidVersions[cachedSerial] = cachedVersion;
              }
              final cachedSdk = sdkVersions[id];
              if (cachedSdk != null) {
                sdkVersions[cachedSerial] = cachedSdk;
              }
            }
            final cachedIp = decoded['ipAddress']?.toString();
            if (cachedIp != null && cachedIp.isNotEmpty && cachedIp != '-') {
              ips[id] = cachedIp;
            }
          } catch (_) {}
        }
      }
    }

    // 智能处理历史离线设备中的网络记录（如鸿蒙 Wi-Fi 设备）：
    // 若网络设备缓存的 serial 仍是网络 ID 本身，尝试通过 IP 地址与同一平台/型号匹配历史物理硬件设备
    for (final id in allIds) {
      if (!isNetworkId(id)) continue;
      final currentSerial = serialMap[id];
      if (currentSerial == null || isNetworkId(currentSerial)) {
        final devIp = ips[id] ??
            (id.contains(':')
                ? id.split(':').first
                : (id.contains('.') ? id : null));
        if (devIp == null || devIp.isEmpty || devIp == '127.0.0.1') continue;

        for (final usbId in allIds) {
          if (isNetworkId(usbId)) continue;
          final usbIp = ips[usbId];
          final sameIp = usbIp == devIp;
          final isSameHarmony =
              products[id] == 'HarmonyOS NEXT' && products[usbId] == 'HarmonyOS NEXT';
          final isSameModel =
              models[id] != null &&
              models[id]!.isNotEmpty &&
              models[id] == models[usbId];

          if (sameIp && (isSameHarmony || isSameModel)) {
            serialMap[id] = usbId;
            final cachedVersion = androidVersions[id];
            if (cachedVersion != null && cachedVersion.isNotEmpty) {
              androidVersions[usbId] ??= cachedVersion;
            }
            final cachedSdk = sdkVersions[id];
            if (cachedSdk != null && cachedSdk > 0) {
              sdkVersions[usbId] ??= cachedSdk;
            }

            final overviewKey = 'devices.overview.$id';
            final cachedJson = prefs.getString(overviewKey);
            if (cachedJson != null) {
              try {
                final map = Map<String, dynamic>.from(jsonDecode(cachedJson));
                map['serial'] = usbId;
                await prefs.setString(overviewKey, jsonEncode(map));
              } catch (_) {}
            }
            break;
          }
        }
      }
    }

    return DeviceRegistryPrefsData(
      historyIds: history,
      aliases: aliases,
      models: models,
      products: products,
      ipAddresses: ips,
      androidVersions: androidVersions,
      sdkVersions: sdkVersions,
      remarks: remarks,
      tags: tags,
      serialMap: serialMap,
    );
  }

  /// 保存 IP 地址字典到本地
  Future<void> saveIps(Map<String, String> ipAddresses) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ipsKey, jsonEncode(ipAddresses));
    } catch (_) {}
  }

  /// 保存系统版本与 SDK 级别字典到本地
  Future<void> saveAndroidVersions(
    Map<String, String> androidVersions,
    Map<String, int> sdkVersions,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_androidVersionsKey, jsonEncode(androidVersions));
      await prefs.setString(_sdkVersionsKey, jsonEncode(sdkVersions));
    } catch (_) {}
  }

  /// 保存历史设备 ID 列表到本地
  Future<void> saveHistory(List<String> historyIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, historyIds);
  }

  /// 保存设备自定义别名字典到本地
  Future<void> saveAliases(Map<String, String> aliases) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aliasesKey, jsonEncode(aliases));
  }

  /// 保存设备型号与产品信息字典到本地
  Future<void> saveModelsAndProducts(
    Map<String, String> models,
    Map<String, String> products,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modelsKey, jsonEncode(models));
      await prefs.setString(_productsKey, jsonEncode(products));
    } catch (_) {}
  }

  /// 保存设备用户备注字典到本地
  Future<void> saveRemarks(Map<String, String> remarks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_remarksKey, jsonEncode(remarks));
  }

  /// 保存设备标签列表字典到本地
  Future<void> saveTags(Map<String, List<String>> tags) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tagsKey, jsonEncode(tags));
  }
}
