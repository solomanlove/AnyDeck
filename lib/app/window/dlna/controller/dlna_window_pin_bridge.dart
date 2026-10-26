import 'package:flutter/services.dart';

/// 连接 DLNA 子窗口标题栏图钉与当前 Flutter Engine 的窗口通道。
class DlnaWindowPinBridge {
  DlnaWindowPinBridge({MethodChannel? channel, MethodChannel? eventsChannel})
    : _channel = channel ?? const MethodChannel('any_deck/window'),
      _eventsChannel =
          eventsChannel ?? const MethodChannel('any_deck/dlna_pin_events');

  final MethodChannel _channel;
  final MethodChannel _eventsChannel;

  /// 原生图钉被点击时，只通知当前子窗口切换状态。
  void listen(Future<void> Function() onTap) {
    _eventsChannel.setMethodCallHandler((call) async {
      if (call.method == 'dlnaPinTapped') await onTap();
    });
  }

  Future<void> setAlwaysOnTop(bool value) =>
      _channel.invokeMethod<void>('setAlwaysOnTop', value);

  /// 标题栏按钮与窗口层级保持同一置顶状态和本地化文案。
  Future<void> update({
    required bool pinned,
    required String pinLabel,
    required String unpinLabel,
  }) => _channel.invokeMethod<void>('setDlnaPin', {
    'pinned': pinned,
    'pinLabel': pinLabel,
    'unpinLabel': unpinLabel,
  });

  void dispose() => _eventsChannel.setMethodCallHandler(null);
}
