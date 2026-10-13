import 'dart:convert';
import 'dart:math';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_window_title_service.dart';
import 'model/desktop_chrome_policy.dart';

const _windowFrameKey = '_windowFrame';
const _windowTitleKey = '_windowTitle';

const Size defaultMirrorWindowSize = Size(480, 800);
const double mirrorWindowTopChromeHeight = 30;
const double mirrorWindowSideChromeWidth = 32;

/// 应用虚拟副屏优先使用手机物理分辨率与 DPI，避免厂商兼容缩放只占左上区域。
String resolveAppMirrorDisplayResolution(
  String? physicalResolution, {
  int? videoWidth,
  int? videoHeight,
}) {
  final physicalMatch = physicalResolution == null
      ? null
      : RegExp(r'(\d+)\s*[xX]\s*(\d+)').firstMatch(physicalResolution);
  if (physicalMatch != null) {
    final first = int.parse(physicalMatch.group(1)!);
    final second = int.parse(physicalMatch.group(2)!);
    final width = min(first, second);
    final height = max(first, second);
    final densityMatch = RegExp(
      r'(\d+)\s*dpi',
      caseSensitive: false,
    ).firstMatch(physicalResolution!);
    final density = densityMatch?.group(1);
    return density == null ? '${width}x$height' : '${width}x$height/$density';
  }

  if (videoWidth != null &&
      videoHeight != null &&
      videoWidth > 0 &&
      videoHeight > 0) {
    final minSide = min(videoWidth, videoHeight);
    final maxSide = max(videoWidth, videoHeight);
    final targetHeight = maxSide < 1920 ? 1920 : maxSide;
    final targetWidth = ((targetHeight * minSide / maxSide).round() ~/ 2) * 2;
    return '${targetWidth}x$targetHeight';
  }
  return '1080x1920';
}

/// 根据设备分辨率或直接指定的宽高比解析投屏初始窗口大小。
/// 竖屏贴合纵向高度，横屏贴合横向适度视野，消除黑边并保证比例精确。
Size resolveMirrorInitialWindowSize(String? resolution, {double? ratio}) {
  final resolvedRatio = ratio ?? parseMirrorAspectRatio(resolution);
  if (resolvedRatio == null || resolvedRatio <= 0) return defaultMirrorWindowSize;

  final double viewerWidth;
  final double viewerHeight;

  if (resolvedRatio >= 1.0) {
    // 横屏：基准宽度 800，高度按比例自适应，保证横屏下有足够的视野与操作空间
    const maxViewerW = 800.0;
    viewerWidth = maxViewerW;
    viewerHeight = viewerWidth / resolvedRatio;
  } else {
    // 竖屏：视频高度使用窗口基准高度扣除 30px 标题栏，宽度按比例自适应。
    final maxViewerH =
        defaultMirrorWindowSize.height - mirrorWindowTopChromeHeight;
    viewerHeight = maxViewerH;
    viewerWidth = viewerHeight * resolvedRatio;
  }

  return Size(
    max(200.0, viewerWidth + mirrorWindowSideChromeWidth),
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
            if (type == 'apk_details' && windowArgs['path'] != arguments['path']) {
              continue;
            }
            if (deviceId == null || windowArgs['deviceId'] == deviceId) {
              if (windowArgs['newDisplay'] == arguments['newDisplay'] &&
                  windowArgs['startApp'] == arguments['startApp']) {
                try {
                  final airplayHandle = arguments['airplayHandle'];
                  if (type == 'mirror' && airplayHandle is int) {
                    await window.invokeMethod('switchIosMirrorSource', {
                      'airplayHandle': airplayHandle,
                      'airplayAspectRatio': arguments['airplayAspectRatio'],
                    });
                  }
                  await window.show();
                  return window;
                } catch (e) {
                  debugPrint('Failed to show existing window, falling back to create: $e');
                  break;
                }
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

  final controller = await WindowController.create(
    WindowConfiguration(
      hiddenAtLaunch: false,
      arguments: jsonEncode(windowArguments),
    ),
  );
  try {
    await controller.show();
  } catch (_) {}
  return controller;
}

/// 在子窗口自己的 Isolate 内应用初始尺寸、位置与标题。
Future<void> configureCurrentAdbManageSubWindow(
  Map<String, dynamic> arguments,
) async {
  try {
    await windowManager.ensureInitialized();

    if (arguments['type'] == 'mirror' ||
        arguments['type'] == 'emulator_manager' ||
        arguments['type'] == 'console' ||
        arguments['type'] == 'version_distribution' ||
        arguments['type'] == 'apk_details') {
      await windowManager.setTitleBarStyle(
        DesktopChromePolicy.current.subWindowTitleBarStyle,
        windowButtonVisibility: true,
      );
    }

    // 投屏窗口的三个控制区允许透出后方桌面；其他子窗口维持实体背景。
    if (arguments['type'] == 'mirror') {
      await windowManager.setBackgroundColor(Colors.transparent);
      try {
        await const MethodChannel(
          'any_deck/window',
        ).invokeMethod<void>('setWindowTransparency', true);
      } on MissingPluginException {
        // 非 macOS 或旧 Runner 没有双层透明通道时，保留 window_manager 的透明背景。
      }
    }

    if (arguments['type'] == 'apk_details') {
      await windowManager.setMinimumSize(const Size(900, 600));
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

    // 尝试同步通知 desktop_multi_window 引擎端展示，做双重可见性保障
    try {
      final controller = await WindowController.fromCurrentEngine();
      await controller.show();
    } catch (_) {}
  } catch (e, stack) {
    debugPrint('configureCurrentAdbManageSubWindow error: $e\n$stack');
  }
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
