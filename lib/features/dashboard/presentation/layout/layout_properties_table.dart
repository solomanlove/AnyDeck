import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../app/l10n/app_localizations.dart';
import '../../../../core/layout_inspector/layout_node.dart';

/// 渲染右侧属性面板，展示当前选中的 XML 节点的所有详细属性，并支持点击复制。
class LayoutPropertiesTable extends StatelessWidget {
  final LayoutNode? selectedNode;

  const LayoutPropertiesTable({super.key, this.selectedNode});

  void _copyToClipboard(BuildContext context, String label, String value) {
    if (value.isEmpty) return;
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${context.l10n.t('copySuccess')}: $value'),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xff09c47c),
        behavior: SnackBarBehavior.floating,
        width: 300,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (selectedNode == null) {
      return Container(
        color: Colors.white,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                context.l10n.t('noComponentSelected'),
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final node = selectedNode!;
    final properties = <_PropertyItem>[
      _PropertyItem(key: 'index', value: node.index.toString()),
      _PropertyItem(key: 'class', value: node.className),
      _PropertyItem(key: 'package', value: node.packageName),
      _PropertyItem(key: 'resource-id', value: node.resourceId),
      _PropertyItem(key: 'text', value: node.text),
      _PropertyItem(key: 'content-desc', value: node.contentDesc),
      _PropertyItem(key: 'bounds', value: node.bounds),
      _PropertyItem(
        key: 'checkable',
        value: node.checkable.toString(),
        isBool: true,
      ),
      _PropertyItem(
        key: 'checked',
        value: node.checked.toString(),
        isBool: true,
      ),
      _PropertyItem(
        key: 'clickable',
        value: node.clickable.toString(),
        isBool: true,
      ),
      _PropertyItem(
        key: 'enabled',
        value: node.enabled.toString(),
        isBool: true,
      ),
      _PropertyItem(
        key: 'focusable',
        value: node.focusable.toString(),
        isBool: true,
      ),
      _PropertyItem(
        key: 'focused',
        value: node.focused.toString(),
        isBool: true,
      ),
      _PropertyItem(
        key: 'scrollable',
        value: node.scrollable.toString(),
        isBool: true,
      ),
      _PropertyItem(
        key: 'long-clickable',
        value: node.longClickable.toString(),
        isBool: true,
      ),
      _PropertyItem(
        key: 'password',
        value: node.password.toString(),
        isBool: true,
      ),
      _PropertyItem(
        key: 'selected',
        value: node.selected.toString(),
        isBool: true,
      ),
    ];

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xfff7f9fa),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.list_alt, size: 18, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Text(
                  context.l10n.t('properties'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.blueGrey,
                  ),
                ),
              ],
            ),
          ),
          // 属性列表内容
          Expanded(
            child: Scrollbar(
              child: ListView.builder(
                itemCount: properties.length,
                itemBuilder: (context, index) {
                  final prop = properties[index];
                  final isEven = index % 2 == 0;
                  final hasValue = prop.value.isNotEmpty;

                  return MouseRegion(
                    cursor: hasValue
                        ? SystemMouseCursors.click
                        : SystemMouseCursors.basic,
                    child: GestureDetector(
                      onTap: hasValue
                          ? () =>
                                _copyToClipboard(context, prop.key, prop.value)
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        color: isEven ? const Color(0xfffafbfc) : Colors.white,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 属性名
                            Expanded(
                              flex: 3,
                              child: Text(
                                prop.key,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xff5f6368),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // 属性值
                            Expanded(
                              flex: 7,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      prop.value.isEmpty ? '-' : prop.value,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: prop.isBool
                                            ? (prop.value == 'true'
                                                  ? const Color(0xff09c47c)
                                                  : Colors.red[600])
                                            : (prop.value.isEmpty
                                                  ? Colors.grey[400]
                                                  : const Color(0xff202124)),
                                        fontWeight: prop.isBool
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  if (hasValue)
                                    Icon(
                                      Icons.copy,
                                      size: 14,
                                      color: Colors.grey[400],
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PropertyItem {
  final String key;
  final String value;
  final bool isBool;

  _PropertyItem({required this.key, required this.value, this.isBool = false});
}
