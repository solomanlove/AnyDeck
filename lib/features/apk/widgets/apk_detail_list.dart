import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/l10n/app_localizations.dart';

/// 可搜索、复制的只读元数据列表。rows 每项以 name 为标题，其余字段为协议元数据。
class ApkDetailList extends StatefulWidget {
  const ApkDetailList({super.key, required this.rows, this.note});
  final List<Map<String, dynamic>> rows;
  final String? note;
  @override
  State<ApkDetailList> createState() => _ApkDetailListState();
}

class _ApkDetailListState extends State<ApkDetailList> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.toLowerCase();
    final filtered = widget.rows
        .where(
          (row) => row.values.any((v) => '$v'.toLowerCase().contains(query)),
        )
        .toList();
    return Column(
      children: [
        if (widget.note != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(widget.note!)),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: context.l10n.t('apkSearch'),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(child: Text(context.l10n.t('apkEmpty')))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final row = filtered[index];
                    final title =
                        row['name']?.toString() ?? context.l10n.t('apkMissing');
                    final details = row.entries
                        .where((e) => e.key != 'name')
                        .map((e) => '${e.key}: ${e.value}')
                        .join('\n');
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 5,
                      ),
                      child: ListTile(
                        title: SelectableText(title),
                        subtitle: details.isEmpty
                            ? null
                            : SelectableText(details),
                        trailing: IconButton(
                          tooltip: context.l10n.t('apkCopy'),
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: '$title\n$details'.trim()),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// 对已知错误码本地化，保留底层诊断输出便于定位损坏文件或安装失败。
String apkErrorText(BuildContext context, Object error) {
  var text = error.toString().replaceFirst('FormatException: ', '');
  for (final key in [
    'apkInvalidFile',
    'apkFileChanged',
    'apkParseFailed',
    'apkParseTimeout',
    'apkCancelled',
    'apkOutputLimit',
    'apkInputLimit',
    'apkDeviceUnavailable',
    'apkResourceWarning',
    'apkSignatureWarning',
    'apkInvalidRequest',
  ]) {
    text = text.replaceAll(key, context.l10n.t(key));
  }
  return text;
}
