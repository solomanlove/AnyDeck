import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 同步 Flutter 本地化标题到桌面系统原生窗口标题栏。
class DesktopWindowTitleService {
  DesktopWindowTitleService._();

  static const _channel = MethodChannel('any_deck/window');

  /// 设置当前桌面窗口标题；移动端或未注册原生通道时静默跳过。
  static Future<void> setTitle(String title) async {
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.fuchsia) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('setWindowTitle', title);
    } on MissingPluginException {
      // 非桌面目标或测试环境没有原生 Runner，忽略即可。
    }
  }
}
