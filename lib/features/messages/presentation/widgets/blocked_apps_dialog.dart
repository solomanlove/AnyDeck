import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/l10n/app_localizations.dart';
import '../../../../core/notifications/notification_providers.dart';
import '../../../../core/providers/app_providers.dart';
import '../controller/messages_controller.dart';

/// 应用屏蔽名单管理弹窗。
class BlockedAppsDialog extends ConsumerStatefulWidget {
  const BlockedAppsDialog({
    super.key,
    required this.deviceId,
    required this.serial,
  });

  final String deviceId;
  final String serial;

  static Future<void> show(
    BuildContext context, {
    required String deviceId,
    required String serial,
  }) {
    return showDialog(
      context: context,
      builder: (_) => BlockedAppsDialog(deviceId: deviceId, serial: serial),
    );
  }

  @override
  ConsumerState<BlockedAppsDialog> createState() => _BlockedAppsDialogState();
}

class _BlockedAppsDialogState extends ConsumerState<BlockedAppsDialog> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final packagesAsync = ref.watch(packagesProvider(widget.deviceId));
    final blockedAsync = ref.watch(blockedAppsProvider(widget.serial));
    final forwardingService =
        ref.read(notificationForwardingServiceProvider);

    final blocked = blockedAsync.value ?? <String>{};
    final packages = packagesAsync.value ?? [];

    final filtered = packages.where((p) {
      if (_filter.isEmpty) return true;
      final q = _filter.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          (p.label != null && p.label!.toLowerCase().contains(q));
    }).toList();

    return AlertDialog(
      title: Row(
        children: [
          const Icon(CupertinoIcons.shield_fill, color: Color(0xff09c47c)),
          const SizedBox(width: 8),
          Text(context.l10n.t('blockedAppsTitle')),
        ],
      ),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            Text(
              context.l10n.t('blockedAppsDesc'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                hintText: context.l10n.t('searchMessagesPlaceholder'),
                prefixIcon: const Icon(CupertinoIcons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (val) => setState(() => _filter = val),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text(context.l10n.t('noMessages')))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final pkg = filtered[index];
                        final isBlocked = blocked.contains(pkg.name);
                        return ListTile(
                          dense: true,
                          title: Text(
                            pkg.label?.isNotEmpty == true
                                ? pkg.label!
                                : pkg.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            pkg.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Switch(
                            value: isBlocked,
                            activeThumbColor: Colors.red,
                            onChanged: (block) async {
                              await forwardingService.toggleBlockApp(
                                widget.serial,
                                pkg.name,
                                block,
                              );
                              ref.invalidate(
                                blockedAppsProvider(widget.serial),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    );
  }
}
