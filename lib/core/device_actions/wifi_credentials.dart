import '../adb/adb_service.dart';

class WifiCredentials {
  final String ssid;
  final String password;
  final String securityType;

  const WifiCredentials({
    required this.ssid,
    required this.password,
    required this.securityType,
  });
}

class WifiCredentialsHelper {
  /// 从 XML 或 conf 文本中解析 WiFi 配置。
  static List<WifiCredentials> parseWifiConfigStore(String content) {
    final List<WifiCredentials> list = [];
    final networkMatches = RegExp(
      r'<Network>([\s\S]*?)</Network>',
    ).allMatches(content);
    for (final netMatch in networkMatches) {
      final block = netMatch.group(1) ?? '';

      final ssidMatch = RegExp(
        r'<string\s+name="SSID">([\s\S]*?)</string>',
      ).firstMatch(block);
      final pskMatch = RegExp(
        r'<string\s+name="PreSharedKey">([\s\S]*?)</string>',
      ).firstMatch(block);
      final wepMatch = RegExp(
        r'<string\s+name="WEPKey">([\s\S]*?)</string>',
      ).firstMatch(block);
      final configKeyMatch = RegExp(
        r'<string\s+name="ConfigKey">([\s\S]*?)</string>',
      ).firstMatch(block);

      var ssid = ssidMatch?.group(1) ?? '';
      var password = pskMatch?.group(1) ?? wepMatch?.group(1) ?? '';
      final configKey = configKeyMatch?.group(1) ?? '';

      ssid = _unescapeXml(ssid);
      if (ssid.startsWith('"') && ssid.endsWith('"') && ssid.length > 1) {
        ssid = ssid.substring(1, ssid.length - 1);
      }

      password = _unescapeXml(password);
      if (password.startsWith('"') &&
          password.endsWith('"') &&
          password.length > 1) {
        password = password.substring(1, password.length - 1);
      }

      if (ssid.isNotEmpty) {
        String securityType = 'WPA/WPA2';
        if (configKey.contains('NONE')) {
          securityType = 'Open';
        } else if (configKey.contains('WEP')) {
          securityType = 'WEP';
        } else if (configKey.contains('SAE') || configKey.contains('WPA3')) {
          securityType = 'WPA3';
        }

        list.add(
          WifiCredentials(
            ssid: ssid,
            password: password,
            securityType: securityType,
          ),
        );
      }
    }
    return list;
  }

  static List<WifiCredentials> parseWpaSupplicant(String content) {
    final List<WifiCredentials> list = [];
    final blocks = content.split('network={');
    for (var i = 1; i < blocks.length; i++) {
      final block = blocks[i].split('}').first;
      final ssidMatch = RegExp(r'ssid="?([^"\n]*)"?').firstMatch(block);
      final pskMatch = RegExp(r'psk="?([^"\n]*)"?').firstMatch(block);
      final keyMgmtMatch = RegExp(r'key_mgmt=([^\n]*)').firstMatch(block);

      final ssid = ssidMatch?.group(1)?.trim() ?? '';
      var password = pskMatch?.group(1)?.trim() ?? '';
      final keyMgmt = keyMgmtMatch?.group(1)?.trim() ?? '';

      if (ssid.isNotEmpty) {
        list.add(
          WifiCredentials(
            ssid: ssid,
            password: password,
            securityType: keyMgmt.isNotEmpty ? keyMgmt : 'WPA/WPA2',
          ),
        );
      }
    }
    return list;
  }

  static String _unescapeXml(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&apos;', "'");
  }

  /// 获取设备上已保存的 WiFi 密码。
  static Future<List<WifiCredentials>> fetchSavedWifi(
    AdbService adb,
    String deviceId,
  ) async {
    // 1. 尝试现代 Android 路径
    var res = await adb.shell(
      deviceId,
      'cat /data/misc/apexdata/com.android.wifi/WifiConfigStore.xml',
    );
    if (res.isSuccess && res.stdout.trim().isNotEmpty) {
      final list = parseWifiConfigStore(res.stdout);
      if (list.isNotEmpty) return list;
    }

    // 2. 尝试 Android 10 路径
    res = await adb.shell(deviceId, 'cat /data/misc/wifi/WifiConfigStore.xml');
    if (res.isSuccess && res.stdout.trim().isNotEmpty) {
      final list = parseWifiConfigStore(res.stdout);
      if (list.isNotEmpty) return list;
    }

    // 3. 尝试旧版 wpa_supplicant 路径
    res = await adb.shell(deviceId, 'cat /data/misc/wifi/wpa_supplicant.conf');
    if (res.isSuccess && res.stdout.trim().isNotEmpty) {
      final list = parseWpaSupplicant(res.stdout);
      if (list.isNotEmpty) return list;
    }

    return [];
  }
}
