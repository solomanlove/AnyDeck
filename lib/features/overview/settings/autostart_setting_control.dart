import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../app/settings/desktop_autostart_service.dart';

/// 系统状态只在入口可见及回到前台时读取，不触发注册或写入偏好。
final autoStartStatusProvider =
    FutureProvider.autoDispose<DesktopAutoStartStatus>(
      (ref) =>
          DesktopAutoStartService.status(registerCancellation: ref.onDispose),
    );

final autoStartUpdateProvider = Provider<Future<void> Function(bool)>(
  (ref) =>
      (enabled) =>
          ref.read(appSettingsProvider.notifier).setLaunchAtStartup(enabled),
);

final autoStartOpenSettingsProvider =
    Provider.autoDispose<Future<void> Function()>(
      (ref) =>
          () => DesktopAutoStartService.openSettings(
            registerCancellation: ref.onDispose,
          ),
    );

/// 常规设置中自启开关旁的系统批准处理；状态以系统查询为准。
///
/// 放入标准设置行的操作区域，管理回焦监听及单次操作，销毁不改变登录项。
class AutoStartSettingControl extends ConsumerStatefulWidget {
  const AutoStartSettingControl({super.key});

  @override
  ConsumerState<AutoStartSettingControl> createState() =>
      _AutoStartSettingControlState();
}

class _AutoStartSettingControlState
    extends ConsumerState<AutoStartSettingControl>
    with WidgetsBindingObserver, WindowListener {
  bool _busy = false;
  String? _errorKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void onWindowFocus() => _refresh();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    if (!mounted || _busy || ref.read(autoStartStatusProvider).isLoading) {
      return;
    }
    setState(() => _errorKey = null);
    ref.invalidate(autoStartStatusProvider);
  }

  Future<void> _perform(Future<void> Function() action, String errorKey) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) _errorKey = errorKey;
    } finally {
      if (mounted) {
        ref.invalidate(autoStartStatusProvider);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final openSettings = ref.watch(autoStartOpenSettingsProvider);
    final result = ref.watch(autoStartStatusProvider);
    final status = result.value;
    final pending = status == DesktopAutoStartStatus.requiresApproval;
    final manual = status == DesktopAutoStartStatus.manual;
    final unavailable = status == DesktopAutoStartStatus.unavailable;
    final unknown = result.hasError || status == DesktopAutoStartStatus.unknown;
    final disabled = _busy || result.isLoading || unavailable || unknown;
    final theme = Theme.of(context);
    final messageKey =
        _errorKey ??
        (result.hasError
            ? 'autoStartReadFailed'
            : switch (status) {
                DesktopAutoStartStatus.requiresApproval =>
                  'autoStartNeedsApproval',
                DesktopAutoStartStatus.manual => 'autoStartManual',
                DesktopAutoStartStatus.unavailable => 'autoStartUnavailable',
                DesktopAutoStartStatus.unknown => 'autoStartReadFailed',
                _ => null,
              });
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CupertinoSwitch(
            key: const ValueKey('autostart-switch'),
            activeTrackColor: theme.colorScheme.primary,
            value:
                status == DesktopAutoStartStatus.enabled || pending || manual,
            onChanged: disabled
                ? null
                : (enabled) => _perform(
                    () => ref.read(autoStartUpdateProvider)(enabled),
                    'autoStartUpdateFailed',
                  ),
          ),
          if (messageKey != null)
            Text(
              context.l10n.t(messageKey),
              key: const ValueKey('autostart-status'),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _errorKey != null || result.hasError
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (pending || manual)
            TextButton(
              key: const ValueKey('autostart-open-settings'),
              onPressed: _busy
                  ? null
                  : () => _perform(openSettings, 'autoStartOpenFailed'),
              child: Text(context.l10n.t('autoStartOpenSettings')),
            ),
          if (unknown || _errorKey != null)
            TextButton(
              key: const ValueKey('autostart-refresh'),
              onPressed: _busy || result.isLoading ? null : _refresh,
              child: Text(context.l10n.t('autoStartRefresh')),
            ),
        ],
      ),
    );
  }
}
