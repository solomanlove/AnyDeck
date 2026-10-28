import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/nearby_share/share_file_progress.dart';
import 'harmony_share_format.dart';

/// 接收中的实际文件字节列表；files 仅含已观察到的项，不补造未知进度或文件名。
/// 字节100%仍显示等待整批结果，取消操作沿用上方整批面板；列表按需构建。
/// 用法：在接收服务活跃时传入 receiveFileProgress 快照。
class HarmonyShareReceiveProgress extends StatelessWidget {
  const HarmonyShareReceiveProgress({super.key, required this.files});
  final List<ShareCoreFileProgress> files;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.t('harmonyShareReceiveFileProgress'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            context.l10n.t('harmonyShareReceiveNamesPending'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: (files.length * 80.0).clamp(80, 240),
            child: ListView.builder(
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download_outlined),
                  title: Text(
                    context.l10n
                        .t('harmonyShareFileIndex')
                        .replaceAll('{index}', '${file.index + 1}'),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${formatShareBytes(file.bytes)} / ${formatShareBytes(file.totalBytes)}',
                      ),
                      LinearProgressIndicator(value: file.fraction),
                      if (file.bytes == file.totalBytes)
                        Text(
                          context.l10n.t('harmonyShareFileBytesComplete'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
