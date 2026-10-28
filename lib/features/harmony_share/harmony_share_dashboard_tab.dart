import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/l10n/app_localizations.dart';
import '../../core/nearby_share/harmony_share_service.dart';
import '../../core/nearby_share/share_core_client.dart';
import '../../core/nearby_share/share_send_selection.dart';
import '../../core/nearby_share/share_transfer_record.dart';
import '../../core/nearby_share/share_record_file_actions.dart';
import '../widgets/dashboard_header_bar.dart';
import '../../app/theme/app_theme_sizes.dart';
import 'widgets/harmony_share_stage.dart';
import 'widgets/harmony_share_panels.dart';
import 'widgets/harmony_share_format.dart';
import 'widgets/harmony_share_queue_panel.dart';
import 'widgets/harmony_share_outbox_panel.dart';
import 'widgets/harmony_share_history_dialog.dart';
import 'widgets/harmony_share_history_recent.dart';
import 'widgets/harmony_share_settings_dialog.dart';

/// 独立互联页面；附近设备与任务状态均来自主窗口常驻服务。
class HarmonyShareDashboardTab extends StatefulWidget {
  const HarmonyShareDashboardTab({super.key});

  @override
  State<HarmonyShareDashboardTab> createState() =>
      _HarmonyShareDashboardTabState();
}

class _HarmonyShareDashboardTabState extends State<HarmonyShareDashboardTab> {
  final _service = HarmonyShareService.instance;
  bool _choosing = false;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _pick(ShareCorePeer peer) async {
    if (_choosing || !_service.canSelectFiles) return;
    _choosing = true;
    try {
      final selected = await openFiles();
      if (selected.isNotEmpty && mounted) {
        await _confirm(peer, selected.map((file) => File(file.path)).toList());
      }
    } finally {
      _choosing = false;
    }
  }

  void _invalidDrop() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.t('harmonyShareDropHint'))),
    );
  }

  Future<void> _confirm(
    ShareCorePeer peer,
    List<File> files, {
    String? retryOf,
  }) async {
    if (!_service.canSelectFiles || _confirming) return;
    _confirming = true;
    try {
      final selection = await ShareSendSelection.inspect(files);
      if (!mounted) return;
      final summary = context.l10n
          .t('harmonyShareSelectionSummary')
          .replaceAll('{count}', '${selection.files.length}')
          .replaceAll('{size}', formatShareBytes(selection.bytes));
      final names = selection.files
          .take(8)
          .map((file) => '${file.name} · ${formatShareBytes(file.bytes)}')
          .join('\n');
      final remaining = selection.files.length > 8
          ? '\n${context.l10n.t('harmonyShareMoreFiles').replaceAll('{count}', '${selection.files.length - 8}')}'
          : '';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => HarmonyShareConfirmDialog(
          receiving: false,
          device: peer.name.isEmpty ? peer.address.address : peer.name,
          summary:
              '$summary\n\n$names$remaining\n\n${context.l10n.t('harmonyShareQueueConfirmHint')}',
        ),
      );
      if (confirmed == true && mounted) {
        if (_service.canAppend) {
          await _service.appendSelection(peer, selection, retryOf: retryOf);
        } else if (!_service.busy) {
          unawaited(_service.sendSelection(peer, selection, retryOf: retryOf));
        } else {
          throw StateError('outbox_cancelling');
        }
      }
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('harmonyShareSelectionLimit'))),
      );
    } on StateError catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(formatShareError('$failure', context.l10n.t))),
      );
    } on FileSystemException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('harmonyShareFileUnavailable'))),
      );
    } finally {
      _confirming = false;
    }
  }

  Future<void> _openRecord(
    ShareTransferRecord record, {
    bool folder = false,
  }) async {
    final opened = await ShareRecordFileActions().open(record, folder: folder);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('harmonyShareOpenError'))),
      );
    }
  }

  Future<void> _retryRecord(ShareTransferRecord record) async {
    final peer = _service.peers[record.address];
    if (!_service.canSelectFiles ||
        peer == null ||
        peer.name != record.deviceName ||
        record.path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('harmonyShareRetryUnavailable'))),
      );
      return;
    }
    await _confirm(peer, [File(record.path!)], retryOf: record.id);
  }

  void _showHistory() {
    final history = _service.history;
    if (history == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => HarmonyShareHistoryDialog(
        history: history,
        legacyPaths: List.of(_service.recent),
        onOpen: _openRecord,
        onFolder: (record) => _openRecord(record, folder: true),
        onRetry: _retryRecord,
      ),
    );
  }

  void _showGuide() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.t('harmonyShareHelp')),
      content: Text(context.l10n.t('harmonyShareGuide')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.t('harmonyShareGotIt')),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final peers = _service.peers.values.toList();
    final status = _service.busy
        ? (_service.receiving
              ? 'harmonyShareReceivingActive'
              : 'harmonyShareSending')
        : _service.error != null
        ? 'harmonyShareUnavailable'
        : _service.enabled
        ? 'harmonyShareFinding'
        : 'harmonyShareDisabled';
    return Column(
      children: [
        DashboardHeaderBar(
          title: context.l10n.t('harmonyShareTitle'),
          subtitle: context.l10n.t('harmonyShareSubtitle'),
          actions: [
            IconButton(
              tooltip: context.l10n.t('harmonyShareSettings'),
              onPressed: () => showDialog<void>(context: context,
                builder: (_) => const HarmonyShareSettingsDialog()),
              icon: const Icon(Icons.settings_outlined),
            ),
            IconButton(
              tooltip: context.l10n.t('harmonyShareScanAgain'),
              onPressed: _service.busy || _service.configuring || !_service.enabled
                  ? null
                  : _service.refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: AppThemeSizes.radiusLarge,
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 24,
                            runSpacing: 12,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.l10n.t('harmonyShareNearby'),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    context.l10n.t('harmonyShareIndependent'),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              Chip(
                                avatar: Icon(
                                  _service.error != null
                                      ? Icons.error_outline
                                      : _service.enabled
                                      ? Icons.radar_rounded
                                      : Icons.pause_circle_outline,
                                  size: 16,
                                ),
                                label: Text(context.l10n.t(status)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      HarmonyShareIdentity(
                        localName: _service.localName,
                        enabled: _service.enabled,
                        onChanged: _service.busy || _service.configuring
                            ? null
                            : (enabled) =>
                                  enabled ? _service.start() : _service.stop(),
                      ),
                      HarmonyShareStage(
                        peers: peers,
                        enabled: _service.enabled,
                        busy: !_service.canSelectFiles,
                        onPick: _pick,
                        onDrop: _confirm,
                        onInvalidDrop: _invalidDrop,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 20,
                          runSpacing: 8,
                          children: [
                            Text(
                              context.l10n.t('harmonyShareHint'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            TextButton(
                              onPressed: _showGuide,
                              child: Text(context.l10n.t('harmonyShareHelp')),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.t('harmonyShareLimit'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_service.error != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: colors.error),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              formatShareError(_service.error!, context.l10n.t),
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                          TextButton(
                            onPressed: _service.busy
                                ? null
                                : _service.enabled
                                ? _service.refresh
                                : _service.start,
                            child: Text(
                              context.l10n.t('harmonyShareScanAgain'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_service.busy &&
                    (_service.receiving ||
                        !_service.sendQueue.nativeBatch ||
                        _service.sendQueue.items.isEmpty)) ...[
                  const SizedBox(height: 12),
                  HarmonyShareTransferPanel(
                    onCancel: _service.cancelTransfer,
                    progress: _service.progress,
                    receiving: _service.receiving,
                    fileName: _service.activeFile,
                  ),
                ],
                if (_service.outbox.entries.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  HarmonyShareOutboxPanel(
                    batches: _service.outbox.waiting,
                    onCancel: _service.outbox.cancel,
                    onCancelAll: _service.cancelTransfer,
                    running: _service.outbox.running,
                    succeeded: _service.outbox.succeeded,
                    failed: _service.outbox.failed,
                    cancelled: _service.outbox.cancelled,
                    onClear: () {
                      _service.outbox.clear();
                      _service.sendQueue.clear();
                    },
                  ),
                ],
                if (_service.sendQueue.items.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  HarmonyShareQueuePanel(
                    items: _service.sendQueue.items,
                    running: _service.sendQueue.running,
                    nativeBatch: _service.sendQueue.nativeBatch,
                    batchTransferredBytes: _service.sendQueue.transferredBytes,
                    cancelling: _service.sendQueue.cancelling,
                    rate: _service.sendQueue.rate,
                    onCancel: _service.sendQueue.cancel,
                    onCancelAll: _service.sendQueue.cancelAll,
                    onClear: _service.sendQueue.clear,
                  ),
                ],
                const SizedBox(height: 20),
                HarmonyShareHistoryRecent(
                  history: _service.history,
                  records: _service.history?.recent ?? const [],
                  storageError: _service.history?.error != null,
                  onHistory: _showHistory,
                  onOpen: _openRecord,
                  onFolder: (record) => _openRecord(record, folder: true),
                  onRetry: _retryRecord,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
