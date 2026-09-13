import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../core/apk/apk_install_controller.dart';
import '../../../core/apk/apk_window_client.dart';
import '../../../core/apk/local_apk_info.dart';
import 'apk_detail_list.dart';

/// 设备选择与安装入口；success 始终指向实际安装的 serial，不受后续选择影响。
class ApkInstallBar extends ConsumerWidget {
  const ApkInstallBar({
    super.key,
    required this.info,
    required this.path,
    required this.mainWindowId,
  });
  final LocalApkInfo info;
  final String path;
  final String mainWindowId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(apkDevicesProvider(mainWindowId));
    final state = ref.watch(apkInstallProvider(mainWindowId));
    final controller = ref.read(apkInstallProvider(mainWindowId).notifier);
    final snapshot = devices.asData?.value;
    final rows = (snapshot?['devices'] as List? ?? [])
        .map((d) => Map<String, dynamic>.from(d as Map))
        .toList();
    final selected = chooseApkDevice(
      rows,
      state.selected,
      snapshot?['preferred'] as String?,
    );
    final error = snapshot?['error'] ?? devices.asError?.error;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null)
            Text(
              '${context.l10n.t('apkAdbError')} ${apkErrorText(context, error)}',
            ),
          if (error == null && rows.isEmpty && !devices.isLoading)
            Text(context.l10n.t('apkNoDevices')),
          if (state.error != null)
            SelectableText(
              apkErrorText(context, state.error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (state.warning != null)
            Text('${context.l10n.t('apkRefreshWarning')} ${state.warning}'),
          if (state.installedSerial != null)
            Text(
              '${context.l10n.t('apkInstalled')} · ${state.installedSerial}',
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(selected),
                  initialValue: selected,
                  isExpanded: true,
                  hint: Text(context.l10n.t('apkChooseDevice')),
                  items: rows
                      .map(
                        (d) => DropdownMenuItem<String>(
                          value: d['id'] as String,
                          enabled: d['online'] == true,
                          child: Text(
                            '${d['name']} · ${d['id']}${d['online'] == true ? '' : ' (${d['status']})'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: state.busy ? null : controller.select,
                ),
              ),
              const SizedBox(width: 16),
              if (state.installedSerial != null) ...[
                OutlinedButton(
                  onPressed: state.busy
                      ? null
                      : () => controller.showInstalled(info.packageName),
                  child: Text(context.l10n.t('apkShowInstalled')),
                ),
                const SizedBox(width: 12),
              ],
              FilledButton.icon(
                onPressed: selected == null || state.busy || !info.installable
                    ? null
                    : () => controller.install(path, selected, info),
                icon: state.busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.install_mobile),
                label: Text(
                  context.l10n.t(state.busy ? 'apkInstalling' : 'apkInstall'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
