import 'package:any_deck/app/theme/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../../app/l10n/app_localizations.dart';
import '../../core/layout_inspector/layout_node.dart';

/// 渲染右侧属性面板，展示当前选中的 XML 节点的所有详细属性，并支持点击复制。
class LayoutPropertiesTable extends StatefulWidget {
  final LayoutNode? selectedNode;
  final bool useDp;
  final double deviceScale;
  final ValueChanged<bool?>? onUseDpChanged;

  const LayoutPropertiesTable({
    super.key,
    this.selectedNode,
    this.useDp = false,
    this.deviceScale = 1.0,
    this.onUseDpChanged,
  });

  @override
  State<LayoutPropertiesTable> createState() => _LayoutPropertiesTableState();
}

class _LayoutPropertiesTableState extends State<LayoutPropertiesTable> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _copyToClipboard(BuildContext context, String label, String value) {
    if (value.isEmpty) return;
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${context.l10n.t('copySuccess')}: $value'),
        duration: const Duration(seconds: 1),
        backgroundColor: AppPalette.primary,
        behavior: SnackBarBehavior.floating,
        width: 300,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (widget.selectedNode == null) {
      return Container(
        color: isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.white.withValues(alpha: 0.2),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(CupertinoIcons.info, size: 48, color: Colors.grey),
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

    final node = widget.selectedNode!;
    final rect = node.rect;
    final parentRect = node.parent?.rect;

    String formatValue(double pxValue) {
      if (widget.useDp) {
        final dpValue = pxValue / widget.deviceScale;
        final dpStr = dpValue
            .toStringAsFixed(1)
            .replaceAll(RegExp(r'\.0$'), '');
        return '${pxValue.round()} px ($dpStr dp)';
      } else {
        return '${pxValue.round()} px';
      }
    }

    String formatBoxValue(double pxValue) {
      final value = widget.useDp ? pxValue / widget.deviceScale : pxValue;
      return value.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    }

    final properties = <_PropertyItem>[
      _PropertyItem(key: 'index', value: node.index.toString()),
      _PropertyItem(key: 'class', value: node.className),
      _PropertyItem(key: 'package', value: node.packageName),
      _PropertyItem(key: 'resource-id', value: node.resourceId),
      _PropertyItem(key: 'text', value: node.text),
      _PropertyItem(key: 'content-desc', value: node.contentDesc),
      _PropertyItem(key: 'bounds', value: node.bounds),
      if (rect != null) ...[
        _PropertyItem(key: 'width', value: formatValue(rect.width)),
        _PropertyItem(key: 'height', value: formatValue(rect.height)),
      ],
      if (rect != null && parentRect != null) ...[
        _PropertyItem(
          key: 'layout_margin_left',
          value: formatValue(rect.left - parentRect.left),
        ),
        _PropertyItem(
          key: 'layout_margin_top',
          value: formatValue(rect.top - parentRect.top),
        ),
        _PropertyItem(
          key: 'layout_margin_right',
          value: formatValue(parentRect.right - rect.right),
        ),
        _PropertyItem(
          key: 'layout_margin_bottom',
          value: formatValue(parentRect.bottom - rect.bottom),
        ),
      ],
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
      color: isDark
          ? Colors.white.withValues(alpha: 0.02)
          : Colors.white.withValues(alpha: 0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.02),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.list_bullet,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.t('properties'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Checkbox(
                  value: widget.useDp,
                  onChanged: widget.onUseDpChanged,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                Text(
                  'DP',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // 属性列表内容
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _scrollController,
                primary: false,
                itemCount: properties.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: _LayoutBoxModel(
                        width: formatBoxValue(rect?.width ?? 0),
                        height: formatBoxValue(rect?.height ?? 0),
                        marginLeft: formatBoxValue(rect != null && parentRect != null ? rect.left - parentRect.left : 0),
                        marginTop: formatBoxValue(rect != null && parentRect != null ? rect.top - parentRect.top : 0),
                        marginRight: formatBoxValue(rect != null && parentRect != null ? parentRect.right - rect.right : 0),
                        marginBottom: formatBoxValue(rect != null && parentRect != null ? parentRect.bottom - rect.bottom : 0),
                      ),
                    );
                  }
                  final prop = properties[index - 1];
                  final isEven = (index - 1) % 2 == 0;
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
                        color: isEven
                            ? (isDark
                                ? Colors.white.withValues(alpha: 0.02)
                                : Colors.black.withValues(alpha: 0.01))
                            : Colors.transparent,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 属性名
                            Expanded(
                              flex: 3,
                              child: Text(
                                prop.key,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.grey[400] : const Color(0xff5f6368),
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
                                                  ? AppPalette.primary
                                                  : (isDark ? Colors.red[300] : Colors.red[600]))
                                            : (prop.value.isEmpty
                                                  ? (isDark ? Colors.grey[600] : Colors.grey[400])
                                                  : (Theme.of(context).colorScheme.onSurface)),
                                        fontWeight: prop.isBool
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  if (hasValue)
                                    Icon(
                                      CupertinoIcons.doc_on_doc,
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

/// 以盒模型方式展示节点尺寸及其相对父节点的四向间距。
class _LayoutBoxModel extends StatelessWidget {
  const _LayoutBoxModel({
    required this.width,
    required this.height,
    required this.marginLeft,
    required this.marginTop,
    required this.marginRight,
    required this.marginBottom,
  });

  final String width;
  final String height;
  final String marginLeft;
  final String marginTop;
  final String marginRight;
  final String marginBottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textStyle = theme.textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontFamily: 'monospace',
      fontWeight: FontWeight.w600,
    );

    return Semantics(
      container: true,
      child: Container(
        key: const ValueKey('layout-box-model'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: AppThemeSizes.radiusSmall,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(marginTop, style: textStyle),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(marginLeft, textAlign: TextAlign.center, style: textStyle)),
                Container(
                  constraints: const BoxConstraints(minWidth: 96, minHeight: 52),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    border: Border.all(color: colorScheme.primary),
                  ),
                  child: Text(
                    '$width × $height',
                    textAlign: TextAlign.center,
                    style: textStyle?.copyWith(color: colorScheme.onPrimaryContainer),
                  ),
                ),
                Expanded(child: Text(marginRight, textAlign: TextAlign.center, style: textStyle)),
              ],
            ),
            const SizedBox(height: 8),
            Text(marginBottom, style: textStyle),
          ],
        ),
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
