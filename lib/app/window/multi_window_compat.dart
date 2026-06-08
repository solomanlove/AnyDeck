import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_window_title_service.dart';

const _windowFrameKey = '_windowFrame';
const _windowTitleKey = '_windowTitle';

/// 封装 desktop_multi_window 0.3.x 的窗口参数，保持业务入口只传语义化数据。
Future<WindowController> createAdbManageWindow({
  required Map<String, dynamic> arguments,
  Rect? frame,
  String? title,
}) {
  final windowArguments = <String, dynamic>{...arguments};
  if (frame != null) {
    windowArguments[_windowFrameKey] = {
      'left': frame.left,
      'top': frame.top,
      'width': frame.width,
      'height': frame.height,
    };
  }
  if (title != null) {
    windowArguments[_windowTitleKey] = title;
  }

  return WindowController.create(
    WindowConfiguration(
      hiddenAtLaunch: true,
      arguments: jsonEncode(windowArguments),
    ),
  );
}

/// 在子窗口自己的 Isolate 内应用初始尺寸、位置与标题。
Future<void> configureCurrentAdbManageSubWindow(
  Map<String, dynamic> arguments,
) async {
  await windowManager.ensureInitialized();

  if (arguments['type'] == 'mirror') {
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: true,
    );
  }

  final frame = _decodeFrame(arguments[_windowFrameKey]);
  final title = arguments[_windowTitleKey] as String?;
  if (frame != null) {
    await windowManager.setBounds(frame);
    await windowManager.center();
  }
  if (title != null && title.isNotEmpty) {
    await DesktopWindowTitleService.setTitle(title);
  }
  await windowManager.show();
  await windowManager.focus();
}

Rect? _decodeFrame(Object? value) {
  if (value is! Map<String, dynamic>) {
    return null;
  }
  final left = (value['left'] as num?)?.toDouble();
  final top = (value['top'] as num?)?.toDouble();
  final width = (value['width'] as num?)?.toDouble();
  final height = (value['height'] as num?)?.toDouble();
  if (left == null || top == null || width == null || height == null) {
    return null;
  }
  return Rect.fromLTWH(left, top, width, height);
}
