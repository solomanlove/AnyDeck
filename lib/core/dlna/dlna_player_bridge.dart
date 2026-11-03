import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// macOS AVPlayer 通道返回的数值可能编码为 int 或 double，统一转换给协议层。
class DlnaPlayerBridge {
  static const channel = MethodChannel('any_deck/dlna_player');
  static const _airplayChannel = MethodChannel('any_deck/airplay_player');

  /// 原生 AVPlayer 窗口由两个协议分别持有，主题变更需同步到两条通道。
  static Future<void> syncAppearance(ThemeMode mode) async {
    for (final player in [channel, _airplayChannel]) {
      try {
        await player.invokeMethod<void>('setAppearance', mode.name);
      } on MissingPluginException {
        // Widget 测试和非 macOS Runner 没有原生播放器通道。
      }
    }
  }

  static Future<double> readNumber(String method, {double fallback = 0}) async {
    final value = await channel.invokeMethod<num>(method);
    return (value ?? fallback).toDouble();
  }
}
