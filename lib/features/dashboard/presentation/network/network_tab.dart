import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/l10n/app_localizations.dart';
import '../../../../core/adb/adb_device.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/providers/network_providers.dart';
import 'network_dialog.dart';

class NetworkTab extends ConsumerWidget {
  const NetworkTab({super.key, required this.device});

  final AdbDevice device;

  void _showAddDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AddPortForwardDialog(deviceId: device.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = ref.watch(deviceOnlineProvider(device.id));

    // 如果设备离线，展示离线提示
    if (!isOnline) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.wifi_exclamationmark,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.t('deviceOffline'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final activeForwardsAsync = ref.watch(
      activePortForwardsProvider(device.id),
    );
    final presets = ref.watch(portForwardPresetsProvider);

    // 触发自动应用（如果在宿主层没有注册，也可以放在这里兜底）
    ref.watch(portForwardAutoApplyProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 端口转发部分 (Port Forwarding)
            _buildSectionHeader(
              context: context,
              title: context.l10n.t('portForwarding'),
              actions: [
                IconButton(
                  tooltip: context.l10n.t('refresh'),
                  icon: const Icon(CupertinoIcons.refresh),
                  onPressed: () =>
                      ref.invalidate(activePortForwardsProvider(device.id)),
                ),
                IconButton(
                  tooltip: context.l10n.t('addPortForward'),
                  icon: const Icon(CupertinoIcons.plus),
                  onPressed: () => _showAddDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            activeForwardsAsync.when(
              data: (forwards) => forwards.isEmpty
                  ? _buildEmptyState(
                      icon: Icons.swap_horiz,
                      title: context.l10n.t('noPortForwards'),
                      subtitle: context.l10n.t('addPortForwardSubtitle'),
                      isDark: isDark,
                    )
                  : _buildActiveForwardsList(context, ref, forwards, isDark),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    err.toString(),
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 36),

            // 保存的预设部分 (Saved Presets)
            _buildSectionHeader(
              context: context,
              title: context.l10n.t('savedPresets'),
              trailingText: '${presets.length}',
            ),
            const SizedBox(height: 16),
            presets.isEmpty
                ? _buildEmptyState(
                    icon: CupertinoIcons.bookmark,
                    title: context.l10n.t('noSavedPresets'),
                    subtitle: context.l10n.t('saveAsPresetSubtitle'),
                    isDark: isDark,
                  )
                : _buildPresetsList(context, ref, presets, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required BuildContext context,
    required String title,
    List<Widget>? actions,
    String? trailingText,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xff1f2937),
          ),
        ),
        if (trailingText != null) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xff334155) : const Color(0xfff3f4f6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              trailingText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[300] : const Color(0xff4b5563),
              ),
            ),
          ),
        ],
        const Spacer(),
        if (actions != null) ...actions,
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff1e293b) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xff334155) : const Color(0xfff3f4f6),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 48,
            color: isDark ? Colors.grey[600] : const Color(0xff9ca3af),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[300] : const Color(0xff374151),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[500] : const Color(0xff9ca3af),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveForwardsList(
    BuildContext context,
    WidgetRef ref,
    List<PortForward> forwards,
    bool isDark,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff1e293b) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xff334155) : const Color(0xfff3f4f6),
        ),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: forwards.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          color: isDark ? const Color(0xff334155) : const Color(0xfff3f4f6),
        ),
        itemBuilder: (context, index) {
          final item = forwards[index];
          return ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.swap_horiz,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
            ),
            title: Row(
              children: [
                Text(
                  'Device: ${item.displayDevicePort}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(
                  CupertinoIcons.arrow_right,
                  size: 14,
                  color: Colors.grey,
                ),
                const SizedBox(width: 12),
                Text(
                  'Local: ${item.displayLocalPort}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.grey[300] : const Color(0xff4b5563),
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(
                CupertinoIcons.trash,
                color: Colors.redAccent,
                size: 18,
              ),
              onPressed: () async {
                final adb = ref.read(adbServiceProvider);
                final devPort = item.devicePort.startsWith('tcp:')
                    ? item.devicePort
                    : 'tcp:${item.devicePort}';
                final result = await adb.run([
                  '-s',
                  device.id,
                  'reverse',
                  '--remove',
                  devPort,
                ]);
                if (result.isSuccess) {
                  ref.invalidate(activePortForwardsProvider(device.id));
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Remove failed: ${result.message}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildPresetsList(
    BuildContext context,
    WidgetRef ref,
    List<PortForwardPreset> presets,
    bool isDark,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff1e293b) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xff334155) : const Color(0xfff3f4f6),
        ),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: presets.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          color: isDark ? const Color(0xff334155) : const Color(0xfff3f4f6),
        ),
        itemBuilder: (context, index) {
          final item = presets[index];
          return ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.bookmark,
                color: Colors.blueAccent,
                size: 20,
              ),
            ),
            title: Text(
              item.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Text(
                    '${item.devicePort} -> ${item.localPort}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.grey[400]
                          : const Color(0xff6b7280),
                    ),
                  ),
                  if (item.autoApply) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Auto-apply',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 应用预设按钮
                TextButton.icon(
                  onPressed: () async {
                    final adb = ref.read(adbServiceProvider);
                    final devPort = item.devicePort.startsWith('tcp:')
                        ? item.devicePort
                        : 'tcp:${item.devicePort}';
                    final locPort = item.localPort.startsWith('tcp:')
                        ? item.localPort
                        : 'tcp:${item.localPort}';
                    final result = await adb.run([
                      '-s',
                      device.id,
                      'reverse',
                      devPort,
                      locPort,
                    ]);
                    if (result.isSuccess) {
                      ref.invalidate(activePortForwardsProvider(device.id));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(context.l10n.t('reverseSuccess')),
                            backgroundColor: const Color(0xff09c47c),
                          ),
                        );
                      }
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${context.l10n.t('reverseFailed')}: ${result.message}',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(CupertinoIcons.play_arrow_solid, size: 12),
                  label: Text(context.l10n.t('apply')),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    CupertinoIcons.trash,
                    color: Colors.grey,
                    size: 18,
                  ),
                  onPressed: () async {
                    await ref
                        .read(portForwardPresetsProvider.notifier)
                        .deletePreset(item);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
