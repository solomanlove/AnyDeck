import 'package:shared_preferences/shared_preferences.dart';

import '../../app/settings/harmony_share_preference_keys.dart';

/// 每轮接收重新读取手动授权；旧配置默认LAN，不能因手机请求而自动启用直连。
abstract final class ShareTransferMode {
  /// 产品入口已收起；忽略历史开启值，正常应用始终使用 LAN。
  /// 保留 resolve 与底层直连实现供后续实验恢复。
  static Future<bool> resolveForApp() async => false;

  static Future<bool> resolve() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getBool(HarmonySharePreferenceKeys.directMode) ?? false;
  }
}
