import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../adb/adb_result.dart';
import '../adb/adb_service.dart';
import 'device_overview.dart';

/// 通过 adb shell 命令收集只读 Android 设备信息。
class DeviceInfoService {
  DeviceInfoService(this._adb);

  final AdbService _adb;

  static const _overviewKeyPrefix = 'devices.overview.';

  Future<void> _saveToCache(String deviceId, DeviceOverview overview) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(overview.toJson());
      await prefs.setString('$_overviewKeyPrefix$deviceId', jsonStr);
    } catch (_) {
      // Ignore cache save errors to prevent breaking the main flow
    }
  }

  Future<DeviceOverview?> loadFromCache(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('$_overviewKeyPrefix$deviceId');
      if (jsonStr != null) {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        return DeviceOverview.fromJson(decoded);
      }
    } catch (_) {
      // Ignore cache load errors to prevent breaking the main flow
    }
    return null;
  }

  /// 并行加载所有概览字段，避免 dashboard 阻塞。
  Future<DeviceOverview> loadOverview(String deviceId) async {
    try {
      // 保持概览能力只读：下面命令只读取系统属性或 proc/sysfs 状态，
      // 打开该面板不会修改手机状态。
      final results = await Future.wait<AdbResult>([
        _adb.shellArgs(deviceId, ['getprop']),
        _adb.run(['-s', deviceId, 'get-serialno']),
        _adb.shellArgs(deviceId, ['uname', '-r']),
        _adb.shellArgs(deviceId, ['nproc']),
        _adb.shellArgs(deviceId, ['wm', 'size']),
        _adb.shellArgs(deviceId, ['wm', 'density']),
        _adb.shellArgs(deviceId, ['settings', 'get', 'system', 'font_scale']),
        _adb.shellArgs(deviceId, ['cat', '/proc/meminfo']),
        _adb.shellArgs(deviceId, ['df', '-k', '/data']),
        _adb.shellArgs(deviceId, ['ip', 'addr', 'show', 'wlan0']),
        _adb.shellArgs(deviceId, ['dumpsys', 'wifi']),
      ]);

      if (!results[0].isSuccess) {
        throw AdbException(results[0].message);
      }

      final properties = _parseGetProp(results[0].stdout);
      final serialFromAdb = _clean(results[1].stdout);
      final kernel = _clean(results[2].stdout);
      final cores = _clean(results[3].stdout);
      final size = _parseWmSize(results[4].stdout);
      final density = _parseWmDensity(results[5].stdout);
      final fontScale = _formatScale(_clean(results[6].stdout));
      final memory = _parseMemory(results[7].stdout);
      final storage = _parseStorage(results[8].stdout);
      final network = results[9].stdout;
      final wifiDump = results[10].stdout;

      final abi = _firstValue(properties, ['ro.product.cpu.abi', 'ro.cpu.abi']);
      final deviceCode = _firstValue(properties, [
        'ro.product.device',
        'ro.product.vendor.device',
      ]);

      final overview = DeviceOverview(
        name: _firstValue(properties, [
          'ro.product.marketname',
          'ro.product.vendor.marketname',
          'ro.product.model',
        ]),
        brand: _firstValue(properties, [
          'ro.product.brand',
          'ro.product.vendor.brand',
          'ro.product.manufacturer',
        ]),
        model: _firstValue(properties, [
          'ro.product.model',
          'ro.product.vendor.model',
        ]),
        serial: _firstValue(properties, [
          'ro.serialno',
          'ro.boot.serialno',
        ], fallback: serialFromAdb),
        androidVersion:
            'Android ${_firstValue(properties, ['ro.build.version.release'])}'
            ' (API ${_firstValue(properties, ['ro.build.version.sdk'])})',
        kernelVersion: kernel,
        processor: _formatProcessor(deviceCode, cores, abi),
        storage: storage,
        memory: memory,
        physicalResolution: _formatResolution(size.physical, density.physical),
        resolution: _formatResolution(size.current, density.current),
        fontScale: fontScale,
        wifi: _parseWifiName(wifiDump),
        ipAddress: _parseIpAddress(network),
        macAddress: _parseMacAddress(network),
      );

      // 保存到本地缓存
      await _saveToCache(deviceId, overview);

      return overview;
    } catch (e) {
      final cached = await loadFromCache(deviceId);
      if (cached != null) {
        return cached;
      }
      rethrow;
    }
  }

  /// 解析 Android getprop 的 `[key]: [value]` 输出。
  Map<String, String> _parseGetProp(String output) {
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

  /// 返回第一个非空且不是 unknown 的属性值。
  String _firstValue(
    Map<String, String> properties,
    List<String> keys, {
    String fallback = '-',
  }) {
    for (final key in keys) {
      final value = properties[key]?.trim();
      if (value != null && value.isNotEmpty && value != 'unknown') {
        return value;
      }
    }
    return fallback.isEmpty ? '-' : fallback;
  }

  /// 从 `wm size` 解析物理尺寸和 override 尺寸。
  _WmSize _parseWmSize(String output) {
    final physical = _matchFirst(output, r'Physical size:\s*(\d+x\d+)');
    final override = _matchFirst(output, r'Override size:\s*(\d+x\d+)');
    return _WmSize(
      physical: physical,
      current: override == '-' ? physical : override,
    );
  }

  /// 从 `wm density` 解析物理密度和 override 密度。
  _WmDensity _parseWmDensity(String output) {
    final physical = _matchFirst(output, r'Physical density:\s*(\d+)');
    final override = _matchFirst(output, r'Override density:\s*(\d+)');
    return _WmDensity(
      physical: physical,
      current: override == '-' ? physical : override,
    );
  }

  /// 将 `/proc/meminfo` 的 MemTotal 转换为紧凑的 GB 字符串。
  String _parseMemory(String output) {
    final kbText = _matchFirst(output, r'MemTotal:\s*(\d+)\s*kB');
    final kb = int.tryParse(kbText);
    if (kb == null) {
      return '-';
    }
    return _formatGb(kb * 1024);
  }

  /// 将 `df -k /data` 转换为已用/总量存储摘要。
  String _parseStorage(String output) {
    // Android toybox df 输出 1K-blocks、Used、Available 列。
    // 这里格式化为“已用 / 总量”，更适合快速查看设备状态。
    final lines = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.length < 2) {
      return '-';
    }
    final columns = lines.last.split(RegExp(r'\s+'));
    if (columns.length < 3) {
      return '-';
    }
    final totalKb = int.tryParse(columns[1]);
    final usedKb = int.tryParse(columns[2]);
    if (totalKb == null || usedKb == null) {
      return '-';
    }
    return '${_formatGb(usedKb * 1024)} / ${_formatGb(totalKb * 1024)}';
  }

  /// 从不同 Android 版本的 dumpsys 输出中提取当前 Wi-Fi SSID。
  String _parseWifiName(String output) {
    // 不同 Android 版本打印 Wi-Fi 状态的格式不同；这里同时覆盖
    // cmd/dumpsys 风格的 "SSID: name" 和 WifiInfo toString 输出。
    final candidates = [
      _matchFirst(output, r'SSID:\s*"([^"\n]+)"'),
      _matchFirst(output, r'SSID:\s*([^,\n]+)'),
      _matchFirst(output, r'mWifiInfo.*?SSID:\s*([^,\n]+)'),
    ];
    for (final candidate in candidates) {
      final value = candidate.replaceAll('"', '').trim();
      if (value.isNotEmpty &&
          value != '-' &&
          value != '<unknown ssid>' &&
          value != '0x') {
        return value;
      }
    }
    return '-';
  }

  /// 从 wlan0 网卡输出中提取 IPv4 地址。
  String _parseIpAddress(String output) {
    return _matchFirst(output, r'inet\s+(\d+\.\d+\.\d+\.\d+)');
  }

  /// 从网卡输出中提取 wlan0 MAC 地址。
  String _parseMacAddress(String output) {
    return _matchFirst(
      output,
      r'link/ether\s+([0-9a-fA-F:]{17})',
    ).toLowerCase();
  }

  /// 将设备代号、CPU 核心数和 ABI 合并为可读的处理器信息。
  String _formatProcessor(String deviceCode, String cores, String abi) {
    final parts = [
      if (deviceCode != '-') deviceCode,
      if (cores != '-') '$cores cores',
      if (abi != '-') '($abi)',
    ];
    return parts.isEmpty ? '-' : parts.join(' ');
  }

  /// 密度可用时，将像素尺寸和 dpi 合并展示。
  String _formatResolution(String size, String density) {
    if (size == '-') {
      return '-';
    }
    return density == '-' ? size : '$size (${density}dpi)';
  }

  /// 将 Android 字体缩放格式化为 `x` 倍率。
  String _formatScale(String raw) {
    final value = double.tryParse(raw);
    if (value == null) {
      return raw.isEmpty ? '-' : raw;
    }
    final text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
    return '${text}x';
  }

  /// 手机存储和内存数值较大，因此使用 GB 格式化字节数。
  String _formatGb(int bytes) {
    final gb = bytes / 1024 / 1024 / 1024;
    return '${gb.toStringAsFixed(2)}G';
  }

  /// 返回正则第一个捕获组；不存在时返回 `-`。
  String _matchFirst(String output, String pattern) {
    return RegExp(pattern, dotAll: true).firstMatch(output)?.group(1)?.trim() ??
        '-';
  }

  /// 规范化单行命令输出。
  String _clean(String output) {
    final lines = output.trim().split('\n');
    return lines.isEmpty ? '-' : lines.first.trim();
  }
}

/// `wm size` 的物理值和当前值。
class _WmSize {
  const _WmSize({required this.physical, required this.current});

  final String physical;
  final String current;
}

/// `wm density` 的物理值和当前值。
class _WmDensity {
  const _WmDensity({required this.physical, required this.current});

  final String physical;
  final String current;
}
