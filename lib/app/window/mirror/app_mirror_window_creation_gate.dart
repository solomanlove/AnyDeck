import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';

import '../multi_window_compat.dart';

/// 主窗口统一串行处理应用投屏窗口创建，覆盖不同 Flutter Engine 的并发点击。
class AppMirrorWindowCreationGate {
  static Future<void> _tail = Future<void>.value();
  static const methodName = 'createAppMirrorWindow';

  static Future<String> create(
    Map<String, dynamic> arguments,
    Size size,
    String title,
  ) async {
    final current = await WindowController.fromCurrentEngine();
    if (current.windowId == '0') {
      return createLocal(arguments, size, title);
    }
    final id = await WindowController.fromWindowId('0')
        .invokeMethod<String>(methodName, {
          'arguments': arguments,
          'width': size.width,
          'height': size.height,
          'title': title,
        });
    if (id == null || id.isEmpty) {
      throw StateError('Main window could not create app mirror window');
    }
    return id;
  }

  /// 先等上一项完成，再检查现有窗口与创建；失败也释放队列。
  static Future<String> createLocal(
    Map<String, dynamic> arguments,
    Size size,
    String title,
  ) async {
    final previous = _tail;
    final completed = Completer<void>();
    _tail = completed.future;
    await previous;
    try {
      final window = await createAdbManageWindow(
        arguments: arguments,
        frame: Offset.zero & size,
        title: title,
      );
      return window.windowId;
    } finally {
      completed.complete();
    }
  }

  /// 仅主窗口注册此处理器，子窗口通过 MethodChannel 请求同一创建队列。
  static Future<dynamic> handleWindowCall(MethodCall call) async {
    if (call.method != methodName) return null;
    final data = call.arguments;
    if (data is! Map ||
        data['arguments'] is! Map ||
        data['width'] is! num ||
        data['height'] is! num ||
        data['title'] is! String) {
      throw ArgumentError('Invalid app mirror window request');
    }
    final arguments = Map<String, dynamic>.from(data['arguments'] as Map);
    if (arguments['type'] != 'mirror') {
      throw ArgumentError('Only mirror windows use this gate');
    }
    return createLocal(
      arguments,
      Size(
        (data['width'] as num).toDouble(),
        (data['height'] as num).toDouble(),
      ),
      data['title'] as String,
    );
  }
}
