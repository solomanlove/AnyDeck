import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../core/nearby_share/harmony_share_service.dart';
import '../../../core/notifications/mac_notification_bridge.dart';
import '../../../core/notifications/notification_providers.dart';
import '../controller/harmony_share_providers.dart';
import 'harmony_share_settings_panel.dart';

/// 主窗口设置弹窗；持有权限查询与选择器生命周期，不改变正在进行的传输。
/// 用法：通过 showDialog 展示，设置写入统一经过 AppSettingsController。
class HarmonyShareSettingsDialog extends ConsumerStatefulWidget {
  const HarmonyShareSettingsDialog({super.key});

  @override
  ConsumerState<HarmonyShareSettingsDialog> createState() => _SettingsState();
}

class _SettingsState extends ConsumerState<HarmonyShareSettingsDialog> {
  final _service = HarmonyShareService.instance;
  late final MacNotificationBridge _bridge;
  bool _saving = false;
  String? _permission;
  String? _errorKey;
  int _permissionRevision = 0;

  @override
  void initState() {
    super.initState();
    _bridge = ref.read(macNotificationBridgeProvider);
    unawaited(_refreshPermission());
  }

  Future<void> _refreshPermission() async {
    final revision = ++_permissionRevision;
    try {
      final status = await _bridge.getAuthorizationStatus().timeout(
        const Duration(seconds: 6),
      );
      if (mounted && revision == _permissionRevision) {
        setState(() => _permission = status);
      }
    } catch (_) {
      if (mounted && revision == _permissionRevision) {
        setState(() => _permission = 'unknown');
      }
    }
  }

  Future<void> _save(Future<void> Function() operation, String errorKey) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _errorKey = null;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted) setState(() => _errorKey = errorKey);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setNotifications(bool enabled) {
    final controller = ref.read(appSettingsProvider.notifier);
    unawaited(
      _save(() async {
        await controller.setHarmonyShareNotifications(enabled);
        if (enabled) {
          final status = await _bridge.getAuthorizationStatus().timeout(
            const Duration(seconds: 6),
          );
          if (status == 'notDetermined' && mounted) {
            await _bridge.requestAuthorization().timeout(
              const Duration(seconds: 30),
            );
          }
          await _refreshPermission();
        }
      }, 'harmonyShareSettingsSaveError'),
    );
  }

  void _setDirectory({bool reset = false}) {
    if (_service.busy) return;
    final controller = ref.read(appSettingsProvider.notifier);
    unawaited(
      _save(() async {
        final path = reset ? '' : await getDirectoryPath();
        if (path == null || !mounted) return;
        if (_service.busy) throw StateError('Transfer active');
        await controller.setHarmonyShareReceiveDirectory(path);
        if (_service.enabled && !_service.busy) await _service.refresh();
      }, 'harmonyShareDirectoryError'),
    );
  }

  void _permissionAction() {
    unawaited(
      _save(() async {
        if (_permission == 'notDetermined') {
          await _bridge.requestAuthorization().timeout(
            const Duration(seconds: 30),
          );
        } else {
          await _bridge.openNotificationSettings().timeout(
            const Duration(seconds: 6),
          );
        }
        await _refreshPermission();
      }, 'harmonyShareSettingsSaveError'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final notifications = ref.read(harmonyShareNotificationsProvider);
    return AlertDialog(
      scrollable: true,
      title: Text(context.l10n.t('harmonyShareSettings')),
      content: AnimatedBuilder(
        animation: Listenable.merge([_service, notifications.deliveryFailed]),
        builder: (context, _) => HarmonyShareSettingsPanel(
          notifications: settings.harmonyShareNotifications,
          directory: settings.harmonyShareReceiveDirectory,
          permission: _permission,
          saving: _saving,
          busy: _service.busy,
          deliveryFailed: notifications.deliveryFailed.value,
          errorKey: _errorKey,
          onNotifications: _setNotifications,
          onChooseDirectory: _setDirectory,
          onResetDirectory: () => _setDirectory(reset: true),
          onPermission: _permissionAction,
          onRefreshPermission: _refreshPermission,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.t('harmonyShareGotIt')),
        ),
      ],
    );
  }
}
