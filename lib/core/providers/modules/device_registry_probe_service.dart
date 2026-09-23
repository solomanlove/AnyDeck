import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../adb/adb_service.dart';
import '../../device_info/device_overview.dart';
import '../../harmony/hdc_service.dart';
import 'device_registry_storage.dart';

/// 设备硬件序列号、局域网 IP 与真实型号探查服务。
///
/// 当检测到新设备上线且缺乏关键元数据（如硬件序列号、WLAN0 IP、Android 版本、真实型号）时，
/// 异步通过 ADB / HDC 底层命令进行非阻塞探测，并持久化到本地 Overview 缓存与 SharedPreferences。
class DeviceRegistryProbeService {
  /// 获取 Android 系统的 Release 版本与 SDK API 级别
  static Future<({String label, int sdk})?> fetchAndroidVersion(
    AdbService adb,
    String id,
  ) async {
    try {
      final releaseResult = await adb.shellArgs(id, [
        'getprop',
        'ro.build.version.release',
      ]);
      final sdkResult = await adb.shellArgs(id, [
        'getprop',
        'ro.build.version.sdk',
      ]);

      final release = releaseResult.isSuccess
          ? releaseResult.stdout.trim()
          : '';
      final sdk = sdkResult.isSuccess ? sdkResult.stdout.trim() : '';
      final sdkVersion = int.tryParse(sdk);
      if (release.isEmpty ||
          release == 'unknown' ||
          sdkVersion == null ||
          sdkVersion <= 0) {
        return null;
      }
      return (label: 'Android $release (API $sdkVersion)', sdk: sdkVersion);
    } catch (_) {
      return null;
    }
  }

  /// 探查 Android 设备的 Wi-Fi 局域网 IP 地址
  static Future<String?> fetchDeviceIpAddress(AdbService adb, String id) async {
    // 优先尝试从本设备的概览缓存获取 IP
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'devices.overview.$id';
      final jsonStr = prefs.getString(cacheKey);
      if (jsonStr != null) {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        final cachedIp = decoded['ipAddress']?.toString();
        if (cachedIp != null && cachedIp.isNotEmpty && cachedIp != '-') {
          return cachedIp;
        }
      }
    } catch (_) {}

    try {
      // 1. 尝试通过 ip route 获取
      final routeResult = await adb.shellArgs(id, ['ip', 'route']);
      if (routeResult.isSuccess) {
        final ip = parseIpFromIpRoute(routeResult.stdout);
        if (ip != null) return ip;
      }

      // 2. 尝试通过 ip addr show wlan0 获取
      final wlanResult = await adb.shellArgs(id, [
        'ip',
        'addr',
        'show',
        'wlan0',
      ]);
      if (wlanResult.isSuccess) {
        final ip = parseIpFromIpAddr(wlanResult.stdout);
        if (ip != null) return ip;
      }

      // 3. 尝试通过 ip addr show 兜底获取
      final addrResult = await adb.shellArgs(id, ['ip', 'addr', 'show']);
      if (addrResult.isSuccess) {
        final ip = parseIpFromIpAddr(addrResult.stdout);
        if (ip != null) return ip;
      }
    } catch (_) {}
    return null;
  }

  static String? parseIpFromIpRoute(String output) {
    final regExp = RegExp(
      r'dev\s+(\S+)\s+.*?\b(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b',
    );
    for (final line in output.split('\n')) {
      final match = regExp.firstMatch(line);
      if (match != null) {
        final ip = match.group(2);
        if (ip != null && ip != '127.0.0.1' && !ip.endsWith('.0')) {
          return ip;
        }
      }
    }
    return null;
  }

  static String? parseIpFromIpAddr(String output) {
    final regExp = RegExp(r'inet\s+(\d+\.\d+\.\d+\.\d+)');
    for (final line in output.split('\n')) {
      final match = regExp.firstMatch(line);
      if (match != null) {
        final ip = match.group(1);
        if (ip != null && ip != '127.0.0.1') {
          return ip;
        }
      }
    }
    return null;
  }

  static String? parseIpFromIfconfig(String output) {
    final regExp = RegExp(r'inet addr:(\d+\.\d+\.\d+\.\d+)');
    for (final line in output.split('\n')) {
      final match = regExp.firstMatch(line);
      if (match != null) {
        final ip = match.group(1);
        if (ip != null && ip != '127.0.0.1') {
          return ip;
        }
      }
    }
    return null;
  }

  /// 异步获取并缓存 Android 设备的物理序列号、系统版本、IP 等
  static Future<({
    String serial,
    String? androidVersion,
    int? sdkVersion,
    String? ipAddress,
  })> probeAndroidDevice({
    required AdbService adb,
    required String id,
    required Map<String, String> androidVersions,
    required Map<String, int> sdkVersions,
  }) async {
    String? versionLabel;
    int? sdkInt;

    final versionInfo = await fetchAndroidVersion(adb, id);
    if (versionInfo != null) {
      versionLabel = versionInfo.label;
      sdkInt = versionInfo.sdk;
    }

    // Try shell getprop ro.serialno first
    var result = await adb.shellArgs(id, ['getprop', 'ro.serialno']);
    var serial = result.isSuccess ? result.stdout.trim() : '';
    if (serial.isEmpty || serial == 'unknown' || serial == '-') {
      final bootResult = await adb.shellArgs(id, [
        'getprop',
        'ro.boot.serialno',
      ]);
      serial = bootResult.isSuccess ? bootResult.stdout.trim() : '';
    }

    if (serial.isEmpty || serial == 'unknown' || serial == '-') {
      final getSerialResult = await adb.run(['-s', id, 'get-serialno']);
      serial = getSerialResult.isSuccess
          ? getSerialResult.stdout.trim()
          : '';
    }

    final effectiveSerial = (serial.isNotEmpty && serial != 'unknown' && serial != '-')
        ? serial
        : id;

    String? ip;
    if (!DeviceRegistryStorage.isNetworkId(id)) {
      ip = await fetchDeviceIpAddress(adb, id);
    }

    // 写入 overview 缓存
    if (effectiveSerial.isNotEmpty && effectiveSerial != id) {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'devices.overview.$id';
      final existingJson = prefs.getString(cacheKey);
      DeviceOverview overview;
      if (existingJson != null) {
        try {
          final decoded = jsonDecode(existingJson) as Map<String, dynamic>;
          overview = DeviceOverview.fromJson(
            decoded,
          ).copyWith(serial: effectiveSerial);
        } catch (_) {
          overview = DeviceOverview.fromJson({}).copyWith(serial: effectiveSerial);
        }
      } else {
        overview = DeviceOverview.fromJson({}).copyWith(serial: effectiveSerial);
      }
      await prefs.setString(cacheKey, jsonEncode(overview.toJson()));
    }

    return (
      serial: effectiveSerial,
      androidVersion: versionLabel,
      sdkVersion: sdkInt,
      ipAddress: ip,
    );
  }

  /// 异步获取并缓存鸿蒙（HarmonyOS NEXT / OpenHarmony）设备的完整参数
  static Future<({
    String serial,
    String? systemVersion,
    int? sdkVersion,
    String? deviceName,
    String? ipAddress,
    String? macAddress,
  })> probeHarmonyDevice({
    required HdcService hdc,
    required String id,
  }) async {
    final paramRes = await hdc.shell(
      id,
      'param get const.ohos.fullname ; param get const.ohos.apiversion ; param get const.product.brand ; param get const.product.model ; param get const.product.name ; param get const.product.software.version ; param get const.product.marketing_name',
    );

    String systemVersion = 'HarmonyOS NEXT';
    int sdkVersion = 23;
    String deviceName = '';

    if (paramRes.isSuccess && paramRes.stdout.isNotEmpty) {
      final lines = const LineSplitter().convert(paramRes.stdout.trim());
      if (lines.length >= 2) {
        final fullname = lines[0].trim();
        final apiVerStr = lines[1].trim();
        final parsedApi = int.tryParse(apiVerStr) ?? 0;
        if (parsedApi > 0) {
          sdkVersion = parsedApi;
        }
        if (fullname.isNotEmpty && !DeviceRegistryStorage.isGenericHarmonyModel(fullname)) {
          systemVersion = '$fullname (API $sdkVersion)';
        } else if (parsedApi > 0) {
          systemVersion = 'HarmonyOS NEXT (API $sdkVersion)';
        }
      }
      bool isValidName(String s) => !DeviceRegistryStorage.isGenericHarmonyModel(s);

      if (lines.length >= 7 && isValidName(lines[6].trim())) {
        deviceName = lines[6].trim();
      } else if (lines.length >= 5 && isValidName(lines[4].trim())) {
        deviceName = lines[4].trim();
      } else if (lines.length >= 4 && isValidName(lines[3].trim())) {
        deviceName = lines[3].trim();
      }
    }

    final rawSerial = await hdc.getDeviceSerial(id);
    final serial = (rawSerial != null && rawSerial.isNotEmpty)
        ? rawSerial
        : (!DeviceRegistryStorage.isNetworkId(id) ? id : null);

    final effectiveSerial = (serial != null && serial.isNotEmpty) ? serial : id;

    String? ip;
    String? harmonyMac;
    final ifconfigRes = await hdc.shell(id, 'ifconfig');
    if (ifconfigRes.isSuccess && ifconfigRes.stdout.isNotEmpty) {
      final parsedIp = parseIpFromIfconfig(ifconfigRes.stdout);
      if (parsedIp != null && parsedIp.isNotEmpty) {
        ip = parsedIp;
      }
      harmonyMac = HdcService.parseMacFromIfconfig(ifconfigRes.stdout);
    }

    // 保存 overview 缓存
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'devices.overview.$id';
    final existingJson = prefs.getString(cacheKey);
    DeviceOverview overview;
    if (existingJson != null) {
      try {
        final decoded = jsonDecode(existingJson) as Map<String, dynamic>;
        overview = DeviceOverview.fromJson(decoded).copyWith(
          serial: effectiveSerial,
          androidVersion: systemVersion,
          name: deviceName.isNotEmpty ? deviceName : null,
          model: deviceName.isNotEmpty ? deviceName : null,
          ipAddress: ip,
          macAddress: harmonyMac ?? decoded['macAddress']?.toString(),
        );
      } catch (_) {
        overview = DeviceOverview(
          name: deviceName.isNotEmpty ? deviceName : id,
          brand: 'HUAWEI',
          model: deviceName.isNotEmpty ? deviceName : 'HarmonyOS Device',
          serial: effectiveSerial,
          androidId: '-',
          androidVersion: systemVersion,
          kernelVersion: 'OpenHarmony',
          processor: '-',
          storage: '-',
          memory: '-',
          physicalResolution: '-',
          resolution: '-',
          logicalDensity: '-',
          refreshRate: '-',
          fontScale: '-',
          wifi: '-',
          wifiEnabled: false,
          ipAddress: ip ?? '-',
          macAddress: harmonyMac ?? '-',
          airplaneModeEnabled: false,
          mobileDataEnabled: false,
          talkbackEnabled: false,
          windowAnimationScale: '1.0',
          transitionAnimationScale: '1.0',
          animatorDurationScale: '1.0',
          rawResolution: '-',
          hwuiProfile: 'false',
          layoutBoundsEnabled: false,
          showTouchesEnabled: false,
          pointerLocationEnabled: false,
          demoModeEnabled: false,
        );
      }
    } else {
      overview = DeviceOverview(
        name: deviceName.isNotEmpty ? deviceName : id,
        brand: 'HUAWEI',
        model: deviceName.isNotEmpty ? deviceName : 'HarmonyOS Device',
        serial: effectiveSerial,
        androidId: '-',
        androidVersion: systemVersion,
        kernelVersion: 'OpenHarmony',
        processor: '-',
        storage: '-',
        memory: '-',
        physicalResolution: '-',
        resolution: '-',
        logicalDensity: '-',
        refreshRate: '-',
        fontScale: '-',
        wifi: '-',
        wifiEnabled: false,
        ipAddress: ip ?? '-',
        macAddress: harmonyMac ?? '-',
        airplaneModeEnabled: false,
        mobileDataEnabled: false,
        talkbackEnabled: false,
        windowAnimationScale: '1.0',
        transitionAnimationScale: '1.0',
        animatorDurationScale: '1.0',
        rawResolution: '-',
        hwuiProfile: 'false',
        layoutBoundsEnabled: false,
        showTouchesEnabled: false,
        pointerLocationEnabled: false,
        demoModeEnabled: false,
      );
    }
    await prefs.setString(cacheKey, jsonEncode(overview.toJson()));
    if (effectiveSerial != id) {
      await prefs.setString(
        'devices.overview.$effectiveSerial',
        jsonEncode(overview.copyWith(serial: effectiveSerial).toJson()),
      );
    }

    return (
      serial: effectiveSerial,
      systemVersion: systemVersion != 'HarmonyOS NEXT' ? systemVersion : null,
      sdkVersion: sdkVersion,
      deviceName: (deviceName.isNotEmpty && !DeviceRegistryStorage.isGenericHarmonyModel(deviceName))
          ? deviceName
          : null,
      ipAddress: ip,
      macAddress: harmonyMac,
    );
  }

  /// 执行 Android 设备探测并写入本地存储与各状态映射
  static Future<void> probeAndSyncAndroid({
    required AdbService adb,
    required String id,
    required Map<String, String> androidVersions,
    required Map<String, int> sdkVersions,
    required Map<String, String> serialMap,
    required Map<String, String> ipAddresses,
    required DeviceRegistryStorage storage,
  }) async {
    try {
      final probed = await probeAndroidDevice(
        adb: adb,
        id: id,
        androidVersions: androidVersions,
        sdkVersions: sdkVersions,
      );
      if (probed.androidVersion != null && probed.sdkVersion != null) {
        androidVersions[id] = probed.androidVersion!;
        sdkVersions[id] = probed.sdkVersion!;
        if (probed.serial != id) {
          androidVersions[probed.serial] = probed.androidVersion!;
          sdkVersions[probed.serial] = probed.sdkVersion!;
        }
        await storage.saveAndroidVersions(androidVersions, sdkVersions);
      }
      serialMap[id] = probed.serial;
      if (probed.ipAddress != null && probed.ipAddress!.isNotEmpty) {
        ipAddresses[id] = probed.ipAddress!;
        if (probed.serial != id) {
          ipAddresses[probed.serial] = probed.ipAddress!;
        }
        await storage.saveIps(ipAddresses);
      }
    } catch (_) {
      serialMap[id] = id;
    }
  }

  /// 执行鸿蒙设备探测并写入本地存储与各状态映射
  static Future<bool> probeAndSyncHarmony({
    required HdcService hdc,
    required String id,
    required Map<String, String> serialMap,
    required Map<String, String> androidVersions,
    required Map<String, int> sdkVersions,
    required Map<String, String> models,
    required Map<String, String> products,
    required Map<String, String> ipAddresses,
    required DeviceRegistryStorage storage,
  }) async {
    try {
      final probed = await probeHarmonyDevice(hdc: hdc, id: id);
      serialMap[id] = probed.serial;
      if (!DeviceRegistryStorage.isNetworkId(probed.serial)) {
        serialMap[probed.serial] = probed.serial;
      }
      if (probed.systemVersion != null && probed.sdkVersion != null) {
        androidVersions[id] = probed.systemVersion!;
        sdkVersions[id] = probed.sdkVersion!;
        if (probed.serial != id) {
          androidVersions[probed.serial] = probed.systemVersion!;
          sdkVersions[probed.serial] = probed.sdkVersion!;
        }
        await storage.saveAndroidVersions(androidVersions, sdkVersions);
      }
      if (probed.deviceName != null && probed.deviceName!.isNotEmpty) {
        models[id] = probed.deviceName!;
        if (probed.serial != id) {
          models[probed.serial] = probed.deviceName!;
        }
        await storage.saveModelsAndProducts(models, products);
      }
      if (probed.ipAddress != null && probed.ipAddress!.isNotEmpty) {
        ipAddresses[id] = probed.ipAddress!;
        if (probed.serial != id) {
          ipAddresses[probed.serial] = probed.ipAddress!;
        }
        await storage.saveIps(ipAddresses);
      }
    } catch (_) {
      serialMap[id] = id;
    }
    return (androidVersions[id] != null &&
            androidVersions[id] != '-' &&
            !DeviceRegistryStorage.isGenericHarmonyModel(androidVersions[id])) &&
        (models[id] != null &&
            !DeviceRegistryStorage.isGenericHarmonyModel(models[id]));
  }
}
