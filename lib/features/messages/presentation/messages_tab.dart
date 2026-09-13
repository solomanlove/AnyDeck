import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/adb/adb_device.dart';
import '../../../core/notifications/notification_models.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/providers/app_providers.dart';
import 'controller/messages_controller.dart';
import 'widgets/messages_header_bar.dart';
import 'widgets/messages_list_view.dart';

/// 消息 Tab 页面（Tab 15），集成转发控制、Companion 授权、过滤及消息历史。
class MessagesTab extends ConsumerStatefulWidget {
  const MessagesTab({super.key, required this.device});

  final AdbDevice device;

  @override
  ConsumerState<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends ConsumerState<MessagesTab> {
  NotificationSessionStatus? _status;
  String _installationId = '';
  int _androidUserId = 0;
  bool _isLoadingStatus = false;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _fetchStatus();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    if (!mounted || _isLoadingStatus) return;
    final isOnline = ref.read(deviceOnlineProvider(widget.device.id));
    if (!isOnline) {
      if (_installationId.isEmpty) {
        final registry = ref.read(deviceRegistryProvider);
        final reg = registry.firstWhere(
          (d) => d.id == widget.device.id,
          orElse: () => RegisteredDevice(
            id: widget.device.id,
            status: widget.device.status,
            isOnline: isOnline,
          ),
        );
        setState(() {
          _installationId =
              (reg.serial?.isNotEmpty == true) ? reg.serial! : widget.device.id;
          _androidUserId = 0;
        });
      }
      return;
    }

    _isLoadingStatus = true;
    try {
      final client = ref.read(notificationForwardingClientProvider);
      final user = await client.getCurrentUser(widget.device.id);
      final status = await client.getStatus(widget.device.id, user);
      if (mounted) {
        setState(() {
          _status = status;
          _installationId = status.installationId;
          _androidUserId = status.androidUserId;
        });
      }
    } catch (_) {
      // 容错处理：使用物理标识作为 installationId
      if (mounted && _installationId.isEmpty) {
        final registry = ref.read(deviceRegistryProvider);
        final reg = registry.firstWhere(
          (d) => d.id == widget.device.id,
          orElse: () => RegisteredDevice(
            id: widget.device.id,
            status: widget.device.status,
            isOnline: isOnline,
          ),
        );
        setState(() {
          _installationId =
              (reg.serial?.isNotEmpty == true) ? reg.serial! : widget.device.id;
          _androidUserId = 0;
        });
      }
    } finally {
      _isLoadingStatus = false;
    }
  }

  Future<void> _handleClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.t('clearMessages')),
        content: Text(context.l10n.t('clearMessagesConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.l10n.t('clearMessages')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final db = await ref.read(notificationDatabaseProvider.future);
      await db.clearMessages(_installationId, _androidUserId);
      final bridge = ref.read(macNotificationBridgeProvider);
      await bridge.removeAllNotifications();

      ref.invalidate(
        deviceMessagesProvider((
          installationId: _installationId,
          userId: _androidUserId,
        )),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(deviceOnlineProvider(widget.device.id));
    final registry = ref.watch(deviceRegistryProvider);
    final reg = registry.firstWhere(
      (d) => d.id == widget.device.id,
      orElse: () => RegisteredDevice(
        id: widget.device.id,
        status: widget.device.status,
        isOnline: isOnline,
      ),
    );
    final serial =
        (reg.serial?.isNotEmpty == true) ? reg.serial! : widget.device.id;

    final effectiveInstallationId =
        _installationId.isNotEmpty ? _installationId : serial;

    final messagesAsync = ref.watch(
      deviceMessagesProvider((
        installationId: effectiveInstallationId,
        userId: _androidUserId,
      )),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          MessagesHeaderBar(
            device: widget.device,
            serial: serial,
            status: _status,
            onClearHistory: _handleClearHistory,
            onRefreshStatus: _fetchStatus,
          ),
          Expanded(
            child: messagesAsync.when(
              data: (messages) => MessagesListView(
                messages: messages,
                deviceId: widget.device.id,
                isOnline: isOnline,
              ),
              loading: () =>
                  const Center(child: CupertinoActivityIndicator()),
              error: (err, _) => Center(
                child: Text(
                  err.toString(),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
