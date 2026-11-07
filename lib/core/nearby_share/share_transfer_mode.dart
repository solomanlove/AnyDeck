import 'package:shared_preferences/shared_preferences.dart';

import '../../app/settings/harmony_share_preference_keys.dart';

/// 每轮接收重新读取手动授权；旧配置默认LAN，不能因手机请求而自动启用直连。
abstract final class ShareTransferMode {
  static Future<bool> resolve() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getBool(HarmonySharePreferenceKeys.directMode) ?? false;
  }
}
