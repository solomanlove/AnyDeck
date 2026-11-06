import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/adb/adb_service.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/app_virtual_display_launcher.dart';
import '../../../core/scrcpy/fusion_mode_preference.dart';
import '../multi_window_compat.dart';
import 'app_mirror_window_creation_gate.dart';

enum AppMirrorLaunchKind { fusion, existingFusion, primary, primaryUnknown }

class AppMirrorLaunchRequest {
  const AppMirrorLaunchRequest({
    required this.deviceId,
    required this.packageName,
    required this.appName,
    required this.mirrorTitleTemplate,
    required this.alwaysOnTop,
    this.device,
    this.physicalDeviceKey,
    this.physicalResolution,
    this.videoWidth,
    this.videoHeight,
    this.forcePrimary = false,
  });

  final String deviceId;
  final String packageName;
  final String appName;
  final String mirrorTitleTemplate;
  final bool alwaysOnTop;
  final RegisteredDevice? device;
  final String? physicalDeviceKey;
  final String? physicalResolution;
  final int? videoWidth;
  final int? videoHeight;
  final bool forcePrimary;
}

class AppMirrorLaunchResult {
  const AppMirrorLaunchResult(this.kind, this.windowId);

  final AppMirrorLaunchKind kind;
  final String windowId;
}

abstract class AppMirrorWindowGateway {
  Future<String?> focusFusion(
    String deviceId,
    String? physicalKey,
    String packageName,
  );
  Future<String> create(
    Map<String, dynamic> arguments,
    Size size,
    String title,
  );
  Future<void> waitForFusionFrame(String windowId);
}

/// 所有应用投屏入口共用的窗口选择与普通主屏启动流程。
class AppMirrorLaunchCoordinator {
  static final _packageNamePattern = RegExp(
    r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$',
  );

  AppMirrorLaunchCoordinator(
    this._adb,
    this._preference, {
    AppMirrorWindowGateway? windows,
    Future<void> Function(String deviceId, String packageName)?
    launchHarmonyApp,
  }) : _windows = windows ?? _DesktopAppMirrorWindowGateway(),
       _launchHarmonyApp = launchHarmonyApp;

  final AdbService _adb;
  final FusionModePreference _preference;
  final AppMirrorWindowGateway _windows;
  final Future<void> Function(String deviceId, String packageName)?
  _launchHarmonyApp;
  final Map<String, Future<AppMirrorLaunchResult>> _inFlight = {};

  /// 同一 Isolate 的重复点击共享启动和首帧等待；跨窗口创建由主窗口队列串行。
  Future<AppMirrorLaunchResult> open(AppMirrorLaunchRequest request) {
    final deviceKey =
        FusionModePreference.knownPhysicalKey(
          request.device,
          request.deviceId,
        ) ??
        request.deviceId;
    final key =
        '$deviceKey\u0000${request.packageName}\u0000${request.forcePrimary}';
    final pending = _inFlight[key];
    if (pending != null) return pending;
    late final Future<AppMirrorLaunchResult> operation;
    operation = _open(request).whenComplete(() {
      if (identical(_inFlight[key], operation)) _inFlight.remove(key);
    });
    _inFlight[key] = operation;
    return operation;
  }

  Future<AppMirrorLaunchResult> _open(AppMirrorLaunchRequest request) async {
    // HarmonyOS 的 aa start 使用 shell 字符串，入口统一校验包名。
    if (!_packageNamePattern.hasMatch(request.packageName)) {
      throw ArgumentError.value(request.packageName, 'packageName');
    }
    final status = await _preference.resolve(
      request.deviceId,
      device: request.device,
      refreshSdk: true,
    );
    final physicalKey =
        request.physicalDeviceKey ??
        status.physicalDeviceKey ??
        FusionModePreference.knownPhysicalKey(request.device, request.deviceId);
    String windowId;
    AppMirrorLaunchKind kind;
    if (!request.forcePrimary &&
        request.device?.isHarmony != true &&
        request.device?.isIos != true) {
      final existing = await _windows.focusFusion(
        request.deviceId,
        physicalKey,
        request.packageName,
      );
      if (existing != null) {
        return AppMirrorLaunchResult(
          AppMirrorLaunchKind.existingFusion,
          existing,
        );
      }
    }
    if (request.device?.isHarmony == true || request.device?.isIos == true) {
      // 其他平台沿用各自投屏服务，不向它们发送 Android display 0 命令。
      if (request.device?.isHarmony == true) {
        final launch = _launchHarmonyApp;
        if (launch == null) {
          throw StateError('HarmonyOS app launcher unavailable');
        }
        await launch(request.deviceId, request.packageName);
      }
      final deviceName = request.device?.customName?.trim().isNotEmpty == true
          ? request.device!.customName!.trim()
          : request.device?.model ?? request.deviceId;
      kind = AppMirrorLaunchKind.primary;
      windowId = await _windows.create(
        {
          'type': 'mirror',
          'deviceId': request.deviceId,
          'deviceName': deviceName,
          'alwaysOnTop': request.alwaysOnTop,
          'isHarmony': request.device?.isHarmony == true,
          'isIos': request.device?.isIos == true,
        },
        resolveMirrorInitialWindowSize(request.physicalResolution),
        request.mirrorTitleTemplate.replaceAll('{name}', deviceName),
      );
    } else if (status.state == FusionModeState.enabled &&
        !request.forcePrimary) {
      final resolution = resolveAppMirrorDisplayResolution(
        request.physicalResolution,
        videoWidth: request.videoWidth,
        videoHeight: request.videoHeight,
      );
      kind = AppMirrorLaunchKind.fusion;
      windowId = await _windows.create(
        {
          'type': 'mirror',
          'deviceId': request.deviceId,
          'physicalDeviceKey': physicalKey,
          'deviceName': request.appName,
          'newDisplay': resolution,
          'startApp': request.packageName,
          'alwaysOnTop': request.alwaysOnTop,
        },
        resolveMirrorInitialWindowSize(resolution),
        request.mirrorTitleTemplate.replaceAll('{name}', request.appName),
      );
    } else {
      // startApp 只用于副屏：普通模式必须先在 display 0 启动。
      await launchAppOnPrimaryDisplay(
        adbService: _adb,
        deviceId: request.deviceId,
        packageName: request.packageName,
      );
      final deviceName = request.device?.customName?.trim().isNotEmpty == true
          ? request.device!.customName!.trim()
          : request.device?.model ?? request.deviceId;
      kind = status.state == FusionModeState.unknown && !request.forcePrimary
          ? AppMirrorLaunchKind.primaryUnknown
          : AppMirrorLaunchKind.primary;
      windowId = await _windows.create(
        {
          'type': 'mirror',
          'deviceId': request.deviceId,
          'physicalDeviceKey': physicalKey,
          'deviceName': deviceName,
          'alwaysOnTop': request.alwaysOnTop,
        },
        resolveMirrorInitialWindowSize(request.physicalResolution),
        request.mirrorTitleTemplate.replaceAll('{name}', deviceName),
      );
    }
    if (kind == AppMirrorLaunchKind.fusion) {
      await _windows.waitForFusionFrame(windowId);
    }
    return AppMirrorLaunchResult(kind, windowId);
  }
}

class _DesktopAppMirrorWindowGateway implements AppMirrorWindowGateway {
  @override
  Future<String?> focusFusion(
    String deviceId,
    String? physicalKey,
    String packageName,
  ) async {
    for (final window in await WindowController.getAll()) {
      try {
        final arguments = jsonDecode(window.arguments);
        if (arguments is! Map ||
            arguments['type'] != 'mirror' ||
            arguments['startApp'] != packageName) {
          continue;
        }
        final sameDevice =
            arguments['deviceId'] == deviceId ||
            (physicalKey != null &&
                arguments['physicalDeviceKey'] == physicalKey);
        if (!sameDevice) {
          continue;
        }
        await window.show();
        return window.windowId;
      } catch (_) {}
    }
    return null;
  }

  @override
  Future<String> create(
    Map<String, dynamic> arguments,
    Size size,
    String title,
  ) async {
    return AppMirrorWindowCreationGate.create(arguments, size, title);
  }

  @override
  Future<void> waitForFusionFrame(String windowId) async {
    final window = WindowController.fromWindowId(windowId);
    final deadline = DateTime.now().add(const Duration(seconds: 55));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final status = await window
            .invokeMethod<Map<dynamic, dynamic>>('mirrorSessionStatus')
            .timeout(const Duration(seconds: 2));
        if (status?['error'] is String) {
          throw StateError(status!['error'] as String);
        }
        if (status?['ready'] == true && status?['displayId'] is int) return;
      } on StateError {
        rethrow;
      } catch (_) {
        // 子窗口 Engine 初始化期间 Channel 尚未就绪。
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    // 超时后要求子窗口自行关闭，释放其 Engine 和投屏资源。
    try {
      await window
          .invokeMethod<void>('closeMirrorWindow')
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
    throw TimeoutException('Fusion mirror first frame timed out');
  }
}

final appMirrorLaunchCoordinatorProvider = Provider<AppMirrorLaunchCoordinator>(
  (ref) {
    return AppMirrorLaunchCoordinator(
      ref.watch(adbServiceProvider),
      ref.watch(fusionModePreferenceProvider),
      launchHarmonyApp: (deviceId, packageName) async {
        final result = await ref
            .read(appManagementServiceProvider)
            .launch(deviceId, packageName, isHarmony: true);
        if (!result.isSuccess) {
          throw StateError('Failed to launch $packageName: ${result.message}');
        }
      },
    );
  },
);
