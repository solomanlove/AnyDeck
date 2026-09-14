import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dal/rust_dal_bridge.dart';

/// WebDriverAgent (WDA) 自动化接口轻量客户端。
/// 通过 RustDalBridge 发送原生底层 HTTP 报文，无需依赖大型 HTTP 第三方库，
/// 毫秒级直连执行 iOS 触控、手势、按键与 UI 树抓取。
class IosWdaClient {
  IosWdaClient({
    this.port = 8100,
    RustDalBridge? bridge,
  }) : _bridge = bridge ?? RustDalBridge.instance;

  final int port;
  final RustDalBridge _bridge;

  /// 发送原始 WDA 请求
  Future<Map<String, dynamic>> request(
    String endpoint, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final bodyJson = body != null ? jsonEncode(body) : null;
    return _bridge.wdaRequest(
      port: port,
      endpoint: endpoint,
      method: method,
      bodyJson: bodyJson,
    );
  }

  /// 获取 WDA 服务运行状态与设备会话详情
  Future<Map<String, dynamic>> getStatus() async {
    return request('/status');
  }

  /// 模拟点击 iPhone 物理 Home 按键 (返回主屏幕)
  Future<bool> pressHome() async {
    final res = await request('/wda/homescreen', method: 'POST');
    return res['success'] == true;
  }

  /// 模拟电源锁屏
  Future<bool> lockScreen() async {
    final res = await request('/wda/lock', method: 'POST');
    return res['success'] == true;
  }

  /// 唤醒并解锁屏幕
  Future<bool> unlockScreen() async {
    final res = await request('/wda/unlock', method: 'POST');
    return res['success'] == true;
  }

  /// 模拟音量与物理按键 (home, volumeUp, volumeDown 等)
  Future<bool> pressButton(String name) async {
    final res = await request(
      '/wda/pressButton',
      method: 'POST',
      body: {'name': name},
    );
    return res['success'] == true;
  }

  /// 在指定物理屏幕坐标 (x, y) 触发轻触点击
  Future<bool> tap(int x, int y) async {
    final res = await request(
      '/wda/tap/nil',
      method: 'POST',
      body: {'x': x, 'y': y},
    );
    return res['success'] == true;
  }

  /// 从起点滑动拖拽到终点坐标 (duration 单位为秒)
  Future<bool> swipe({
    required int fromX,
    required int fromY,
    required int toX,
    required int toY,
    double duration = 0.5,
  }) async {
    final res = await request(
      '/wda/dragfromtoforduration',
      method: 'POST',
      body: {
        'fromX': fromX,
        'fromY': fromY,
        'toX': toX,
        'toY': toY,
        'duration': duration,
      },
    );
    return res['success'] == true;
  }

  /// 注入键盘文本
  Future<bool> inputText(String text) async {
    final characters = text.split('');
    final res = await request(
      '/wda/keys',
      method: 'POST',
      body: {'value': characters},
    );
    return res['success'] == true;
  }

  /// 获取前台 UI 层次树 XML/JSON
  Future<String> getUiSource() async {
    final res = await request('/source');
    final payload = res['payload'];
    if (payload is String) return payload;
    return jsonEncode(payload);
  }

  /// 获取设备当前截屏 (Base64 解码后的 PNG 二进制)
  Future<Uint8List?> captureScreenshot() async {
    final res = await request('/screenshot');
    final payload = res['payload'];
    if (payload is Map<String, dynamic>) {
      final value = payload['value'] as String?;
      if (value != null && value.isNotEmpty) {
        try {
          return base64Decode(value);
        } catch (e) {
          debugPrint('[IosWdaClient] Base64 截图解码失败: $e');
        }
      }
    }
    return null;
  }
}

/// 默认端口 (8100) 的 WDA 客户端 Provider
final iosWdaClientProvider = Provider<IosWdaClient>((ref) {
  return IosWdaClient();
});

/// 支持动态自定义端口的 WDA 客户端 Provider
final iosWdaClientFamily = Provider.family<IosWdaClient, int>((ref, port) {
  return IosWdaClient(port: port);
});
