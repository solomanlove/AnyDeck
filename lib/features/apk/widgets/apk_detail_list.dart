import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/l10n/app_localizations.dart';

/// 可搜索、复制的只读元数据列表。
///
/// 支持解析并展示组件（如 Activity）的独立图标、真实标题（Label）与完整类名（Name）。
/// [rows] 每项为组件或协议元数据 Map。
/// [fallbackIcon] 当组件没有独立图标时，用于兜底展示的应用图标。
/// [showComponentIcon] 是否在没有独立图标时仍展示兜底图标/组件占位图标（针对 Activity 等视觉组件启用）。
class ApkDetailList extends StatefulWidget {
  const ApkDetailList({
    super.key,
    required this.rows,
    this.note,
    this.fallbackIcon,
    this.showComponentIcon = false,
  });

  final List<Map<String, dynamic>> rows;
  final String? note;
  final Uint8List? fallbackIcon;
  final bool showComponentIcon;

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
    final filtered = widget.rows.where((row) {
      return row.entries.any((e) {
        if (e.key == 'icon') return false;
        return '${e.value}'.toLowerCase().contains(query);
      });
    }).toList();
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
                    final name = row['name']?.toString() ?? context.l10n.t('apkMissing');
                    final label = row['label']?.toString();
                    final hasResolvedLabel = label != null &&
                        label.isNotEmpty &&
                        label != name;
                    final primaryTitle = hasResolvedLabel ? label : name;

                    // 提取图标：优先组件自身独立图标，Activity 视觉组件开启兜底应用图标
                    Widget? leadingWidget;
                    final iconBase64 = row['icon'] as String?;
                    if (iconBase64 != null && iconBase64.isNotEmpty) {
                      try {
                        final bytes = base64Decode(iconBase64);
                        leadingWidget = ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            bytes,
                            width: 36,
                            height: 36,
                            fit: BoxFit.contain,
                          ),
                        );
                      } catch (_) {}
                    }
                    if (leadingWidget == null && widget.showComponentIcon) {
                      if (widget.fallbackIcon != null) {
                        leadingWidget = ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            widget.fallbackIcon!,
                            width: 36,
                            height: 36,
                            fit: BoxFit.contain,
                          ),
                        );
                      } else {
                        leadingWidget = Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            Icons.widgets_outlined,
                            size: 20,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        );
                      }
                    }

                    // 构建副标题与详情文本（排除 Base64 二进制内容，规整资源引用名）
                    final detailLines = <String>[];
                    if (hasResolvedLabel && row['name'] != null) {
                      detailLines.add(name);
                    }
                    for (final entry in row.entries) {
                      if (entry.key == 'name' || entry.key == 'icon') continue;
                      if (entry.key == 'rawIcon') {
                        detailLines.add('icon: ${entry.value}');
                        continue;
                      }
                      if (entry.key == 'rawLabel') {
                        continue;
                      }
                      if (entry.key == 'label' && row['rawLabel'] != null) {
                        detailLines.add('label: ${entry.value} (${row['rawLabel']})');
                        continue;
                      }
                      detailLines.add('${entry.key}: ${entry.value}');
                    }
                    final details = detailLines.join('\n');

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 5,
                      ),
                      child: ListTile(
                        leading: leadingWidget,
                        title: SelectableText(
                          primaryTitle,
                          style: hasResolvedLabel
                              ? const TextStyle(fontWeight: FontWeight.w600)
                              : null,
                        ),
                        subtitle: details.isEmpty
                            ? null
                            : SelectableText(details),
                        trailing: IconButton(
                          tooltip: context.l10n.t('apkCopy'),
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: '$primaryTitle\n$details'.trim()),
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
