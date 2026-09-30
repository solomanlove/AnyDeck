import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/adb/adb_device.dart';
import '../../../core/notifications/notification_models.dart';
import '../../../core/notifications/notification_device_identity.dart';
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
  int _deviceGeneration = 0;
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
  void didUpdateWidget(covariant MessagesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id) {
      _deviceGeneration++;
      _status = null;
      _installationId = '';
      _androidUserId = 0;
      _isLoadingStatus = false;
      _fetchStatus();
    }
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
      return;
    }

    _isLoadingStatus = true;
    final generation = _deviceGeneration;
    final deviceId = widget.device.id;
    try {
      final client = ref.read(notificationForwardingClientProvider);
      final user = await client.getCurrentUser(deviceId);
      final status = await client.getStatus(deviceId, user);
      if (!mounted || generation != _deviceGeneration) return;
      final registry = ref.read(deviceRegistryProvider);
      final reg = registry.firstWhere(
        (d) =>
            d.id == widget.device.id ||
            d.serial == widget.device.id ||
            d.connections.contains(widget.device.id),
        orElse: () => RegisteredDevice(
          id: widget.device.id,
          status: widget.device.status,
          isOnline: isOnline,
        ),
      );
      final serial = (reg.serial?.isNotEmpty == true)
          ? reg.serial!
          : widget.device.id;
      if (status.installationId.isNotEmpty) {
        final identity = resolveNotificationIdentity(
          devices: registry,
          deviceId: deviceId,
          serial: serial,
          installationId: status.installationId,
          fallbackName: context.l10n.t('messageAndroidDevice'),
        );
        final database = await ref.read(notificationDatabaseProvider.future);
        if (!mounted || generation != _deviceGeneration) return;
        await database.linkSource(
          [serial, widget.device.id, ...reg.connections],
          status.installationId,
          status.androidUserId,
          identity: identity,
        );
        if (!mounted || generation != _deviceGeneration) return;
        ref.invalidate(notificationSourceProvider(serial));
      }
      if (mounted && generation == _deviceGeneration) {
        setState(() {
          _status = status;
          _installationId = status.installationId;
          _androidUserId = status.androidUserId;
        });
      }
    } catch (_) {
      // 状态轮询失败时保留最近一次已知来源，离线历史由数据库映射恢复。
    } finally {
      if (generation == _deviceGeneration) _isLoadingStatus = false;
    }
  }

  Future<void> _handleClearHistory(
    NotificationSource source,
    String deviceLabel,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.t('clearMessages')),
        content: Text(
          '${context.l10n.t('clearMessagesConfirm')}\n$deviceLabel',
        ),
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
      await db.clearMessages(source.installationId, source.androidUserId);
      final bridge = ref.read(macNotificationBridgeProvider);
      await bridge.removeNotificationsWithPrefix(
        'notif_${source.installationId}_${source.androidUserId}_',
      );

      ref.invalidate(
        deviceMessagesProvider((
          installationId: source.installationId,
          userId: source.androidUserId,
        )),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(deviceOnlineProvider(widget.device.id));
    final registry = ref.watch(deviceRegistryProvider);
    final reg = registry.firstWhere(
      (d) =>
          d.id == widget.device.id ||
          d.serial == widget.device.id ||
          d.connections.contains(widget.device.id),
      orElse: () => RegisteredDevice(
        id: widget.device.id,
        status: widget.device.status,
        isOnline: isOnline,
      ),
    );
    final serial = (reg.serial?.isNotEmpty == true)
        ? reg.serial!
        : widget.device.id;
    final storedSource = ref.watch(notificationSourceProvider(serial)).value;
    final currentSource = _installationId.isNotEmpty
        ? NotificationSource(
            installationId: _installationId,
            androidUserId: _androidUserId,
            identity:
                storedSource?.installationId == _installationId &&
                    storedSource?.androidUserId == _androidUserId
                ? storedSource?.identity
                : null,
          )
        : storedSource;

    final target = ref.watch(messageClickTargetProvider);
    final isTargetDevice =
        target != null &&
        (target.serial != null
            ? target.serial == serial
            : target.deviceId == widget.device.id);
    final source = isTargetDevice
        ? ref
                  .watch(
                    messageSourceDetailsProvider((
                      installationId: target.installationId,
                      userId: target.userId,
                    )),
                  )
                  .value ??
              NotificationSource(
                installationId: target.installationId,
                androidUserId: target.userId,
              )
        : currentSource;
    final identity = resolveNotificationIdentity(
      devices: registry,
      deviceId: widget.device.id,
      serial: serial,
      installationId: source?.installationId ?? '',
      fallbackName: context.l10n.t('messageAndroidDevice'),
      snapshot: source?.identity,
    );
    final deviceLabel = identity.label(notificationKnownDeviceIds(registry));

    final messagesAsync = source == null
        ? const AsyncValue<List<NotificationMessage>>.data([])
        : ref.watch(
            deviceMessagesProvider((
              installationId: source.installationId,
              userId: source.androidUserId,
            )),
          );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          MessagesHeaderBar(
            device: widget.device,
            serial: serial,
            deviceLabel: deviceLabel,
            status: _status,
            onClearHistory: source == null
                ? () {}
                : () => _handleClearHistory(source, deviceLabel),
            onRefreshStatus: _fetchStatus,
          ),
          if (isTargetDevice && source != null && currentSource != null &&
              (source.installationId != currentSource.installationId ||
                  source.androidUserId != currentSource.androidUserId))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  ref.read(messageClickTargetProvider.notifier).state = null;
                  ref.read(targetMessageIdProvider.notifier).state = null;
                },
                child: Text(context.l10n.t('messageReturnToCurrentSource')),
              ),
            ),
          Expanded(
            child: messagesAsync.when(
              data: (messages) => MessagesListView(
                messages: messages,
                deviceId: widget.device.id,
                deviceLabel: deviceLabel,
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
