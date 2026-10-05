import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/ios/ios_process_info.dart';

/// iOS 进程信息卡：展示进程与宿主应用，Bundle ID 可选中复制。
///
/// [process] 为关联后的进程信息；[onKill] 由页面执行确认及结束操作，
/// 传 null 禁用按钮。例如 `IosProcessTile(process: item, onKill: onStop)`。
class IosProcessTile extends StatelessWidget {
  const IosProcessTile({super.key, required this.process, this.onKill});

  final IosProcessInfo process;
  final VoidCallback? onKill;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final app = process.app;
    final bundleId = app?.bundleId ?? process.bundleId;
    final metadata = [
      '${l10n.t('iosProcessPid')}: ${process.pid}',
      if (process.isExtension)
        l10n.t('iosProcessExtension')
      else if (process.isApplication == true)
        l10n.t('iosProcessApplication'),
      if (app != null) l10n.t(app.system ? 'iosSystemApp' : 'iosUserApp'),
      if (app?.version != null) '${l10n.t('iosAppVersion')}: ${app!.version}',
    ];
    final path = process.executablePath;
    final startedAt = process.startedAt;
    return Card(
      child: ListTile(
        leading: Icon(process.isExtension ? Icons.extension : Icons.memory),
        title: Text(process.displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (bundleId != null)
              SelectableText(
                '${l10n.t(process.isExtension && app != null ? 'iosProcessHostBundleId' : 'iosBundleId')}: $bundleId',
              ),
            if (process.bundleId != null && process.bundleId != bundleId)
              SelectableText('${l10n.t('iosBundleId')}: ${process.bundleId}'),
            Text(metadata.join(' · ')),
            if (startedAt != null)
              Text(
                '${l10n.t('iosProcessStartedAt')}: ${startedAt.toLocal().toIso8601String().split('.').first.replaceFirst('T', ' ')}',
              ),
            if (path != null)
              Tooltip(
                message: '${l10n.t('iosProcessExecutablePath')}: $path',
                child: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
        trailing: IconButton(
          tooltip: l10n.t('iosKillProcess'),
          onPressed: onKill,
          icon: Icon(
            Icons.stop_circle_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ),
    );
  }
}
