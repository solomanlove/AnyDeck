import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/l10n/app_localizations.dart';
import '../../core/nearby_share/harmony_share_service.dart';
import '../../core/nearby_share/share_core_client.dart';
import '../widgets/dashboard_header_bar.dart';

/// 独立互联页面；附近设备与任务状态均来自主窗口常驻服务。
class HarmonyShareDashboardTab extends StatefulWidget {
  const HarmonyShareDashboardTab({super.key});

  @override
  State<HarmonyShareDashboardTab> createState() =>
      _HarmonyShareDashboardTabState();
}

class _HarmonyShareDashboardTabState extends State<HarmonyShareDashboardTab> {
  final _service = HarmonyShareService.instance;
  bool _dragging = false;

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
    final selected = await openFile();
    if (selected != null && mounted) await _confirm(peer, File(selected.path));
  }

  Future<void> _confirm(ShareCorePeer peer, File file) async {
    final stat = await file.stat();
    if (!mounted) return;
    if (stat.type != FileSystemEntityType.file ||
        stat.size == 0 ||
        stat.size > 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('harmonyShareLimit'))),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('harmonyShareConfirm')),
        content: Text(
          '${file.uri.pathSegments.last} · ${stat.size} B\n${peer.name}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.t('shareTestCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.t('harmonyShareConfirm')),
          ),
        ],
      ),
    );
    if (confirmed == true) await _service.send(peer, file);
  }

  Future<void> _pickTarget() async {
    if (_service.peers.length == 1) {
      await _pick(_service.peers.values.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final peers = _service.peers.values.toList();
    return Column(
      children: [
        DashboardHeaderBar(
          title: context.l10n.t('harmonyShareTitle'),
          subtitle: context.l10n.t('harmonyShareSubtitle'),
          actions: [
            IconButton(
              tooltip: context.l10n.t('harmonyShareScanAgain'),
              onPressed: _service.busy ? null : _service.refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.t('harmonyShareNearby'),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(context.l10n.t('harmonyShareLimit')),
                        ],
                      ),
                    ),
                    Chip(
                      label: Text(
                        _service.busy
                            ? context.l10n.t('harmonyShareSending')
                            : _service.error != null
                            ? context.l10n.t('harmonyShareUnavailable')
                            : context.l10n.t('harmonyShareFinding'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Icon(
                          Icons.laptop_mac_rounded,
                          color: colors.primary,
                          size: 34,
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.l10n.t('harmonyShareIdentity')),
                            Text(
                              context.l10n.t('harmonyShareIdentityName'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const Spacer(),
                        Switch(
                          value: _service.enabled,
                          onChanged: (enabled) =>
                              enabled ? _service.start() : _service.stop(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                DropTarget(
                  onDragEntered: (_) => setState(() => _dragging = true),
                  onDragExited: (_) => setState(() => _dragging = false),
                  onDragDone: (detail) {
                    setState(() => _dragging = false);
                    if (detail.files.length == 1 && peers.length == 1) {
                      _confirm(peers.first, File(detail.files.first.path));
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 260),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: _dragging
                          ? colors.primaryContainer
                          : colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _dragging
                            ? colors.primary
                            : colors.outlineVariant,
                      ),
                    ),
                    child: Column(
                      children: [
                        Wrap(
                          spacing: 18,
                          runSpacing: 18,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final peer in peers)
                              DropTarget(
                                onDragDone: (detail) {
                                  if (detail.files.length == 1 &&
                                      !_service.busy) {
                                    _confirm(
                                      peer,
                                      File(detail.files.first.path),
                                    );
                                  }
                                },
                                child: ActionChip(
                                  avatar: const Icon(Icons.smartphone_rounded),
                                  label: Text(
                                    peer.name.isEmpty
                                        ? peer.address.address
                                        : peer.name,
                                  ),
                                  onPressed: _service.busy
                                      ? null
                                      : () => _pick(peer),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 26),
                        Icon(
                          Icons.share_rounded,
                          color: colors.primary,
                          size: 42,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          peers.isEmpty
                              ? context.l10n.t('harmonyShareEmpty')
                              : context.l10n.t('harmonyShareDrop'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: peers.length == 1 && !_service.busy
                              ? _pickTarget
                              : null,
                          child: Text(context.l10n.t('harmonySharePick')),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(context.l10n.t('harmonyShareHint')),
                if (_service.error != null) ...[
                  const SizedBox(height: 12),
                  Text(_service.error!, style: TextStyle(color: colors.error)),
                ],
                if (_service.busy) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _service.cancelTransfer,
                    child: Text(context.l10n.t('shareTestCancel')),
                  ),
                ],
                const SizedBox(height: 28),
                Text(
                  context.l10n.t('harmonyShareRecent'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (_service.recent.isEmpty)
                  Text(context.l10n.t('harmonyShareNoRecent')),
                for (final path in _service.recent.take(8))
                  ListTile(
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(File(path).uri.pathSegments.last),
                    subtitle: Text(path),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
