import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../core/adb/adb_device.dart';
import '../../core/network/port_forward_command.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/network_providers.dart';
import 'network_dialog.dart';
import 'network_section_widgets.dart';

/// 正向 TCP 映射区；[device] 指定当前设备，用于查询、添加和删除规则。
class ForwardPortPanel extends ConsumerStatefulWidget {
  const ForwardPortPanel({super.key, required this.device});

  final AdbDevice device;

  @override
  ConsumerState<ForwardPortPanel> createState() => _ForwardPortPanelState();
}

class _ForwardPortPanelState extends ConsumerState<ForwardPortPanel> {
  String? _removingPort;

  Future<void> _remove(PortForward rule) async {
    if (_removingPort != null) return;
    setState(() => _removingPort = rule.localPort);
    final adb = ref.read(adbServiceProvider);
    final result = await PortForwardCommand.removeForward(
      adb,
      widget.device.isHarmony ? ref.read(hdcServiceProvider) : null,
      deviceId: widget.device.id,
      isHarmony: widget.device.isHarmony,
      localPort: int.parse(rule.displayLocalPort),
      devicePort: int.parse(rule.displayDevicePort),
    );
    if (!mounted) return;
    setState(() => _removingPort = null);
    if (result.isSuccess) {
      ref.invalidate(activeForwardPortsProvider(widget.device.id));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.l10n.t('forwardRemoveFailed')}: ${result.message}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rules = ref.watch(activeForwardPortsProvider(widget.device.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              context.l10n.t('forwardPortForwarding'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            IconButton(
              tooltip: context.l10n.t('addForwardPort'),
              icon: const Icon(Icons.add),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AddPortForwardDialog(
                  deviceId: widget.device.id,
                  isForward: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        rules.when(
          data: (items) => items.isEmpty
              ? NetworkEmptyState(
                  icon: Icons.swap_horiz,
                  title: context.l10n.t('noForwardPorts'),
                  subtitle: context.l10n.t('forwardPortSubtitle'),
                )
              : Card(
                  color: colors.surface.withValues(alpha: 0.35),
                  child: Column(
                    children: [
                      for (final rule in items)
                        ListTile(
                          leading: Icon(
                            Icons.arrow_forward,
                            color: colors.primary,
                          ),
                          title: Text(
                            '${context.l10n.t('localPort')}: ${rule.displayLocalPort} → '
                            '${context.l10n.t('devicePort')}: ${rule.displayDevicePort}',
                          ),
                          trailing: IconButton(
                            tooltip: context.l10n.t('removePortForward'),
                            icon: _removingPort == rule.localPort
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.delete_outline),
                            onPressed: _removingPort == null
                                ? () => _remove(rule)
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text(
            '${context.l10n.t('forwardListFailed')}: $error',
            style: TextStyle(color: colors.error),
          ),
        ),
      ],
    );
  }
}
