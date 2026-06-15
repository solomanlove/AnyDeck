import 'dart:convert';
import 'dart:math';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_window_title_service.dart';

const _windowFrameKey = '_windowFrame';
const _windowTitleKey = '_windowTitle';

const Size defaultMirrorWindowSize = Size(480, 800);
const double mirrorWindowTopChromeHeight = 58;

/// 根据设备分辨率解析投屏初始窗口大小。
Size resolveMirrorInitialWindowSize(String? resolution) {
  final ratio = parseMirrorAspectRatio(resolution);
  if (ratio == null) return defaultMirrorWindowSize;

  final viewerMaxWidth = defaultMirrorWindowSize.width;
  final viewerMaxHeight =
      defaultMirrorWindowSize.height - mirrorWindowTopChromeHeight;
  final containerRatio = viewerMaxWidth / viewerMaxHeight;

  final double viewerWidth;
  final double viewerHeight;
  if (containerRatio > ratio) {
    viewerHeight = viewerMaxHeight;
    viewerWidth = viewerHeight * ratio;
  } else {
    viewerWidth = viewerMaxWidth;
    viewerHeight = viewerWidth / ratio;
  }

  return Size(
    max(200.0, viewerWidth),
    max(200.0, viewerHeight + mirrorWindowTopChromeHeight),
  );
}

/// 解析投屏画面宽高比。
double? parseMirrorAspectRatio(String? resolution) {
  if (resolution == null || resolution == '-') return null;
  final match = RegExp(r'(\d+)\s*[xX]\s*(\d+)').firstMatch(resolution);
  if (match == null) return null;

  final width = int.tryParse(match.group(1)!);
  final height = int.tryParse(match.group(2)!);
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }
  return width / height;
}

/// 封装 desktop_multi_window 0.3.x 的窗口参数，保持业务入口只传语义化数据。
Future<WindowController> createAdbManageWindow({
  required Map<String, dynamic> arguments,
  Rect? frame,
  String? title,
}) async {
  final type = arguments['type'] as String?;
  final deviceId = arguments['deviceId'] as String?;
  if (type != null) {
    try {
      final windows = await WindowController.getAll();
      for (final window in windows) {
        if (window.arguments.isEmpty) continue;
        try {
          final windowArgs = jsonDecode(window.arguments);
          if (windowArgs is Map && windowArgs['type'] == type) {
            if (deviceId == null || windowArgs['deviceId'] == deviceId) {
              if (windowArgs['newDisplay'] == arguments['newDisplay'] &&
                  windowArgs['startApp'] == arguments['startApp']) {
                await window.show();
                return window;
              }
            }
          }
        } catch (e) {
          debugPrint('Failed to parse window arguments: $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to check existing windows: $e');
    }
  }

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

  if (arguments['type'] == 'mirror' || arguments['type'] == 'emulator_manager' || arguments['type'] == 'console') {
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
