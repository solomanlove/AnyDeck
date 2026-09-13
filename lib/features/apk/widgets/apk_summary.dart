import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../core/apk/local_apk_info.dart';

/// APK 概况侧栏；info 为静态快照，path 是宿主机文件而非设备安装路径。
class ApkSummary extends StatelessWidget {
  const ApkSummary({super.key, required this.info, required this.path});
  final LocalApkInfo info;
  final String path;
  @override
  Widget build(BuildContext context) {
    final icon = info.icon;
    final fallback = Icon(
      Icons.android,
      size: 72,
      color: Theme.of(context).colorScheme.primary,
    );
    final fields = {
      'apkPackage': info.packageName,
      'apkVersion': [
        info.text('versionName'),
        if (info.text('versionCode').isNotEmpty)
          '(${info.text('versionCode')})',
      ].where((part) => part.isNotEmpty).join(' '),
      'apkMinSdk': info.text('minSdk'),
      'apkTargetSdk': info.text('targetSdk'),
      'apkMaxSdk': info.text('maxSdk'),
      'apkSize':
          '${((info.data['size'] as num? ?? 0) / 1024 / 1024).toStringAsFixed(2)} MB',
      'apkFile': path,
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SizedBox.square(
              dimension: 96,
              child: icon == null
                  ? fallback
                  : Image.memory(
                      icon,
                      cacheWidth: 192,
                      errorBuilder: (_, _, _) => fallback,
                    ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            info.name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(info.text('abis'), textAlign: TextAlign.center),
          if (info.data['debuggable'] == true)
            Center(child: Chip(label: Text(context.l10n.t('apkDebug')))),
          const Divider(height: 40),
          for (final field in fields.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.t(field.key),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SelectableText(
                          field.value.isEmpty
                              ? context.l10n.t('apkMissing')
                              : field.value,
                        ),
                      ),
                      if (field.key == 'apkPackage' || field.key == 'apkFile')
                        IconButton(
                          tooltip: context.l10n.t('apkCopy'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                          icon: const Icon(Icons.copy, size: 16),
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: field.value),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
