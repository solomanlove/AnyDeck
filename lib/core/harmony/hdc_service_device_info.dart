import 'dart:convert';

import 'hdc_service.dart';

/// 鸿蒙设备信息与标识解析扩展
extension HdcServiceDeviceInfo on HdcService {
  /// 判断目标标识是否为网络/无线地址 (如 IP 或带端口的地址)
  static bool isNetworkId(String id) {
    return id.contains(':') || id.contains('.') || id == '127.0.0.1';
  }

  /// 校验鸿蒙设备型号、名称或输出是否为通用占位符或异常错误提示（如 Please wait, Fail, Error, [E00...]）
  static bool isGenericOrInvalidModel(String? s) {
    if (s == null || s.trim().isEmpty) return true;
    final lower = s.toLowerCase().trim();
    return lower == 'harmonyos device' ||
        lower == 'harmonyos next device' ||
        lower == 'harmonyos' ||
        lower.startsWith('harmonyos device') ||
        lower.startsWith('harmonyos next') ||
        lower == 'openharmony' ||
        lower == '-' ||
        lower == 'unknown' ||
        lower.contains('fail') ||
        lower.contains('error') ||
        lower.contains('errnum') ||
        lower.contains('please wait') ||
        lower.contains('channel') ||
        lower.contains('get parameter') ||
        lower.contains('[e0') ||
        lower.contains('[fail]') ||
        lower.contains('[info]') ||
        lower.contains('daemon') ||
        lower.contains('timeout') ||
        lower.contains('not match') ||
        lower.length > 50;
  }

  /// 从 `param get` 输出中解析物理序列号 (SN)
  static String? parseSerialFromParamOutput(String output) {
    final lines = const LineSplitter().convert(output);
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isNotEmpty && !isGenericOrInvalidModel(line)) {
        return line;
      }
    }
    return null;
  }

  /// 从 `bm get -u` 输出中解析 UDID 标识
  static String? parseUdidFromBmOutput(String output) {
    // 部分 HDC 版本会把提示语与 64 位 UDID 分两行输出：
    // `udid of current device is :\n<UDID>`。UDID 不能复用型号校验，
    // 因为型号校验会把长度超过 50 的合法 UDID 判为异常。
    final labeledMatch = RegExp(
      r'\budid\b[^\r\n]*[:：]\s*([a-zA-Z0-9_-]{10,128})',
      caseSensitive: false,
    ).firstMatch(output);
    final labeledUdid = labeledMatch?.group(1);
    if (labeledUdid != null) {
      return labeledUdid;
    }

    for (final rawLine in const LineSplitter().convert(output)) {
      final line = rawLine.trim();
      if (RegExp(r'^[a-zA-Z0-9_-]{10,128}$').hasMatch(line)) {
        return line;
      }
    }
    return null;
  }

  /// 从 `nproc`、HarmonyOS ABI 参数和 `uname -m` 的组合输出中解析 CPU 概要。
  ///
  /// 该结果只表示设备公开的逻辑核心数与 CPU ABI，不把架构误写成具体 SoC 型号。
  static String? parseCpuSummary(String output) {
    final lines = const LineSplitter()
        .convert(output)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;

    final cores = int.tryParse(lines.first);
    if (cores == null || cores <= 0) return null;

    final architecture = lines
        .skip(1)
        .firstWhere((line) => !isGenericOrInvalidModel(line), orElse: () => '');
    return architecture.isEmpty
        ? '$cores cores'
        : '$cores cores ($architecture)';
  }

  /// 仅对已确认的硬件型号补充 SoC 名称，其余设备保留 HDC 实测的 CPU 信息。
  static String formatProcessor(String model, String? cpuSummary) {
    final chipset = switch (model.trim().toUpperCase()) {
      'ADA-AL00U' => 'Kirin 9000SL',
      _ => null,
    };
    if (chipset == null) return cpuSummary ?? '-';
    return cpuSummary == null ? chipset : '$chipset · $cpuSummary';
  }

  /// 从 WifiDevice 的系统能力输出中提取当前已连接网络的 SSID。
  static String? parseWifiSsid(String output) {
    if (!RegExp(
      r'^\s*WiFi connection status:\s*connected\s*$',
      caseSensitive: false,
      multiLine: true,
    ).hasMatch(output)) {
      return null;
    }
    final ssid = RegExp(
      r'^\s*Connection\.ssid:\s*(.+?)\s*$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(output)?.group(1)?.trim();
    if (ssid == null || ssid.isEmpty || ssid == '<unknown ssid>') return null;
    return ssid;
  }

  /// `uname -a` 中的构建编号及日期会变化，概览只展示内核标识和版本。
  static String? parseKernelVersion(String output) {
    final version = output.trim().split('#').first.trim();
    return version.isEmpty ? null : version;
  }

  /// 获取鸿蒙设备的真实硬件序列号 (SN)。
  ///
  /// 优先通过 `param get ohos.boot.sn` 等参数获取底层硬件序列号；
  /// 若未能获取，尝试 `bm get -u` 查询 UDID；
  /// 若为非网络设备（如 USB 标识），则以 `deviceId` 本身作为兜底。
  Future<String?> getDeviceSerial(String deviceId) async {
    final isNet = isNetworkId(deviceId);
    try {
      final paramRes = await shell(
        deviceId,
        'param get ohos.boot.sn ; param get const.product.serial ; param get const.product.sn ; param get const.product.udid',
        timeout: const Duration(seconds: 4),
      );
      if (paramRes.isSuccess && paramRes.stdout.isNotEmpty) {
        final sn = parseSerialFromParamOutput(paramRes.stdout);
        if (sn != null && sn.isNotEmpty) {
          return sn;
        }
      }

      final bmRes = await shell(
        deviceId,
        'bm get -u',
        timeout: const Duration(seconds: 3),
      );
      if (bmRes.isSuccess && bmRes.stdout.isNotEmpty) {
        final udid = parseUdidFromBmOutput(bmRes.stdout);
        if (udid != null && udid.isNotEmpty) {
          return udid;
        }
      }
    } catch (_) {}

    if (!isNet) {
      return deviceId;
    }
    return null;
  }
}
