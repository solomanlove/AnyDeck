import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device_actions/foreground_app_service.dart';
import '../../../core/providers/app_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../widget/app_toast.dart';

typedef ForegroundAppDisplayNameResolver = String? Function(String packageName);

/// 处理投屏工具栏返回键长按：先提示前台应用，持续按住则强停非桌面应用。
class MirrorBackLongPressHandler {
  MirrorBackLongPressHandler({
    required this.ref,
    required this.deviceId,
    required this.displayNameResolver,
  });

  final WidgetRef ref;
  final String deviceId;
  final ForegroundAppDisplayNameResolver displayNameResolver;

  Timer? _previewTimer;
  Timer? _forceStopTimer;
  ForegroundAppInfo? _targetInfo;
  bool _pointerDown = false;
  bool _longPressTriggered = false;

  bool get shouldSuppressBack => _longPressTriggered;

  void handlePointerDown(BuildContext context) {
    cancel();
    _pointerDown = true;
    _longPressTriggered = false;
    _previewTimer = Timer(const Duration(milliseconds: 450), () {
      _previewTarget(context);
    });
    _forceStopTimer = Timer(const Duration(milliseconds: 1200), () {
      _forceStopTarget(context);
    });
  }

  void handlePointerUp() {
    _pointerDown = false;
    _previewTimer?.cancel();
    _forceStopTimer?.cancel();
  }

  void cancel() {
    _pointerDown = false;
    _previewTimer?.cancel();
    _forceStopTimer?.cancel();
    _previewTimer = null;
    _forceStopTimer = null;
    _targetInfo = null;
  }

  Future<void> _previewTarget(BuildContext context) async {
    if (!_pointerDown) {
      return;
    }
    _longPressTriggered = true;
    try {
      final info = await ref
          .read(foregroundAppServiceProvider)
          .foregroundApp(deviceId);
      _targetInfo = info;
      if (!context.mounted || !_pointerDown) {
        return;
      }
      final displayName = _resolveDisplayName(info);
      _showFloatingMessage(
        context,
        info.isHome
            ? context.l10n.t('homeScreen')
            : context.l10n
                  .t('currentForegroundApp')
                  .replaceAll('{app}', displayName),
      );
    } catch (e) {
      if (context.mounted && _pointerDown) {
        _showFloatingMessage(
          context,
          context.l10n
              .t('getCurrentAppFailed')
              .replaceAll('{error}', e.toString()),
          isError: true,
        );
      }
    }
  }

  Future<void> _forceStopTarget(BuildContext context) async {
    if (!_pointerDown) {
      return;
    }
    try {
      final service = ref.read(foregroundAppServiceProvider);
      final info = _targetInfo ?? await service.foregroundApp(deviceId);
      _targetInfo = info;
      if (!context.mounted || !_pointerDown) {
        return;
      }
      if (info.isHome || info.packageName.isEmpty) {
        _showFloatingMessage(context, context.l10n.t('homeScreen'));
        return;
      }

      final result = await service.forceStopPackage(deviceId, info.packageName);
      if (!context.mounted || !_pointerDown) {
        return;
      }
      final displayName = _resolveDisplayName(info);
      _showFloatingMessage(
        context,
        result.isSuccess
            ? context.l10n
                  .t('forceStopAppSuccess')
                  .replaceAll('{app}', displayName)
            : context.l10n
                  .t('forceStopAppFailed')
                  .replaceAll('{error}', result.message),
        isError: !result.isSuccess,
      );
    } catch (e) {
      if (context.mounted && _pointerDown) {
        _showFloatingMessage(
          context,
          context.l10n
              .t('forceStopAppFailed')
              .replaceAll('{error}', e.toString()),
          isError: true,
        );
      }
    }
  }

  String _resolveDisplayName(ForegroundAppInfo info) {
    final resolved = displayNameResolver(info.packageName)?.trim();
    if (resolved != null && resolved.isNotEmpty) {
      return resolved;
    }
    return info.displayName;
  }

  void _showFloatingMessage(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    AppToast.show(context, message, isError: isError);
  }
}
