import 'dart:io';

import 'package:flutter/services.dart';

import 'host_network_info.dart';

/// 读取电脑网络信息；macOS 使用 CoreWLAN，不执行需要 sudo 的诊断命令。
class HostNetworkService {
  static const _channel = MethodChannel('any_deck/host_network');
  static const _timeout = Duration(seconds: 5);

  Future<HostNetworkInfo> read() async {
    Map<Object?, Object?>? snapshot;
    if (Platform.isMacOS) {
      try {
        snapshot = await _channel
            .invokeMapMethod<Object?, Object?>('read')
            .timeout(_timeout);
      } catch (_) {
        // 原生接口失败或尚未重新编译时触发轻量命令行回退。
      }
      final hasNativeSsid = (snapshot?['wifiInterfaces'] as List? ?? [])
          .whereType<Map>()
          .any((w) => (w['ssid'] as String?)?.isNotEmpty == true);
      if (!hasNativeSsid) {
        final fallbackSsid = await _fallbackReadMacWifiSsid();
        if (fallbackSsid != null && fallbackSsid.isNotEmpty) {
          final wifiList = (snapshot?['wifiInterfaces'] as List? ?? []).toList();
          if (wifiList.isEmpty) {
            wifiList.add({
              'name': 'en0',
              'ssid': fallbackSsid,
              'connected': true,
            });
          } else {
            for (var i = 0; i < wifiList.length; i++) {
              final item = wifiList[i];
              if (item is Map) {
                final map = Map<String, dynamic>.from(item);
                map['ssid'] = fallbackSsid;
                wifiList[i] = map;
                break;
              }
            }
          }
          final updated = Map<Object?, Object?>.from(snapshot ?? {});
          updated['wifiInterfaces'] = wifiList;
          updated['locationAuthorized'] = true;
          snapshot = updated;
        }
      }
    }
    final addresses = <HostNetworkAddress>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      ).timeout(_timeout);
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          addresses.add(HostNetworkAddress(interface.name, address.address));
        }
      }
    } catch (_) {
      // IP 获取失败不影响已读取的 Wi-Fi 名称。
    }
    return HostNetworkInfo.resolve(snapshot, addresses);
  }

  /// 在原生通道不可用或未授权时，通过系统 CoreWLAN 扫描缓存提取手机热点/Wi-Fi 名称。
  static Future<String?> _fallbackReadMacWifiSsid() async {
    if (!Platform.isMacOS) return null;
    try {
      final result = await Process.run(
        'swift',
        [
          '-e',
          'import CoreWLAN; if let iface = CWWiFiClient.shared().interface() { if let s = iface.ssid(), !s.isEmpty { print(s) } else { let ch = iface.wlanChannel()?.channelNumber ?? 0; let curR = iface.rssiValue(); let c = (iface.cachedScanResults() ?? []).filter { \$0.wlanChannel?.channelNumber == ch && \$0.ssid != nil && !\$0.ssid!.isEmpty }; if let best = (c.sorted { abs(\$0.rssiValue - curR) < abs(\$1.rssiValue - curR) }).first?.ssid { print(best) } } }',
        ],
      ).timeout(const Duration(seconds: 4));
      final out = (result.stdout as String?)?.trim();
      if (out != null && out.isNotEmpty && !out.contains('error:')) {
        return out;
      }
    } catch (_) {}
    return null;
  }

  /// 仅用户点击时请求名称读取权限；已拒绝时跳转系统定位设置。
  Future<void> requestWifiAccess() async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod<void>('requestWifiAccess').timeout(_timeout);
  }
}
