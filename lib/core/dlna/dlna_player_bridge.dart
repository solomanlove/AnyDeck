import 'package:flutter/services.dart';

/// macOS AVPlayer 通道返回的数值可能编码为 int 或 double，统一转换给协议层。
class DlnaPlayerBridge {
  static const channel = MethodChannel('any_deck/dlna_player');

  static Future<double> readNumber(String method, {double fallback = 0}) async {
    final value = await channel.invokeMethod<num>(method);
    return (value ?? fallback).toDouble();
  }
}
