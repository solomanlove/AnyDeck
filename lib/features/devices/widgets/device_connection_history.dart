import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/emulator/emulator_connection.dart';
import '../../../core/providers/modules/registered_device_model.dart';

/// 展示 [device] 各模拟器端口最近一次连接的起止时间和时长。
///
/// 在线时每秒刷新时长。[now] 提供当前时间，默认使用系统时钟。
class DeviceConnectionHistory extends StatefulWidget {
  const DeviceConnectionHistory({
    super.key,
    required this.device,
    this.now = DateTime.now,
  });

  final RegisteredDevice device;
  final DateTime Function() now;

  @override
  State<DeviceConnectionHistory> createState() =>
      _DeviceConnectionHistoryState();
}

class _DeviceConnectionHistoryState extends State<DeviceConnectionHistory> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(DeviceConnectionHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool _isRunning(EmulatorConnectionHistoryEntry entry) =>
      entry.disconnectedAt == null &&
      widget.device.isOnline &&
      widget.device.connections.contains(entry.id);

  void _syncTimer() {
    final hasRunningTime = widget.device.connectionHistory.any(
      (entry) => entry.connectedAt != null && _isRunning(entry),
    );
    if (hasRunningTime) {
      _timer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  String? _formatTime(DateTime? value) =>
      value?.toLocal().toString().split('.').first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.t('deviceConnectionHistory'),
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        for (final entry in widget.device.connectionHistory.reversed)
          _buildEntry(context, entry),
      ],
    );
  }

  Widget _buildEntry(
    BuildContext context,
    EmulatorConnectionHistoryEntry entry,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final timeStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final running = _isRunning(entry);
    final start = entry.connectedAt;
    final end = running ? widget.now() : entry.disconnectedAt;
    final elapsed = start == null || end == null ? null : end.difference(start);
    final unknown = l10n.t('deviceConnectionTimeUnknown');
    final startText = _formatTime(start) ?? unknown;
    final endText = running
        ? l10n.t('deviceConnectionInProgress')
        : _formatTime(end) ?? unknown;
    final durationText = elapsed == null
        ? l10n.t('deviceConnectionDurationUnknown')
        : l10n.formatDuration(elapsed.isNegative ? Duration.zero : elapsed);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              SelectableText(entry.id, style: theme.textTheme.bodySmall),
              if (running)
                Text(
                  l10n.t('deviceCurrentConnection'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                '${l10n.t('deviceConnectionStartedAt')}  $startText',
                style: timeStyle,
              ),
              Text(
                '${l10n.t('deviceConnectionEndedAt')}  $endText',
                style: timeStyle,
              ),
              Text(
                '${l10n.t('deviceConnectionDuration')}  $durationText',
                style: timeStyle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
