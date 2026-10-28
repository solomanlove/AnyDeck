import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/l10n/app_localizations.dart';
import '../../core/nearby_share/harmony_share_service.dart';
import '../../core/nearby_share/share_core_client.dart';
import '../widgets/dashboard_header_bar.dart';
import '../../app/theme/app_theme_sizes.dart';
import 'widgets/harmony_share_stage.dart';
import 'widgets/harmony_share_panels.dart';

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
    if (_choosing || _service.busy) return;
    _choosing = true;
    try {
      final selected = await openFile();
      if (selected != null && mounted) {
        await _confirm(peer, File(selected.path));
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

  Future<void> _confirm(ShareCorePeer peer, File file) async {
    if (_service.busy || _confirming) return;
    _confirming = true;
    try {
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
        builder: (_) => HarmonyShareConfirmDialog(
          receiving: false,
          device: peer.name.isEmpty ? peer.address.address : peer.name,
          summary: '${file.uri.pathSegments.last} · ${stat.size} B',
        ),
      );
      if (confirmed == true && mounted) await _service.send(peer, file);
    } on FileSystemException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('harmonyShareFileUnavailable'))),
      );
    } finally {
      _confirming = false;
    }
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
        ? 'harmonyShareSending'
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
              tooltip: context.l10n.t('harmonyShareScanAgain'),
              onPressed: _service.busy || !_service.enabled
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
                        enabled: _service.enabled,
                        onChanged: _service.busy
                            ? null
                            : (enabled) =>
                                  enabled ? _service.start() : _service.stop(),
                      ),
                      HarmonyShareStage(
                        peers: peers,
                        enabled: _service.enabled,
                        busy: _service.busy,
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
                              _service.error!,
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
                if (_service.busy) ...[
                  const SizedBox(height: 12),
                  HarmonyShareTransferPanel(onCancel: _service.cancelTransfer),
                ],
                const SizedBox(height: 20),
                HarmonyShareRecent(paths: _service.recent),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
