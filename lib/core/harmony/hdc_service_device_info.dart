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
    if (isGenericOrInvalidModel(output)) return null;
    final match = RegExp(r'(?:udid:?\s*)?([a-zA-Z0-9_-]{10,})').firstMatch(output.trim());
    if (match != null) {
      final udid = match.group(1);
      if (udid != null && !isGenericOrInvalidModel(udid)) {
        return udid;
      }
    }
    return null;
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
