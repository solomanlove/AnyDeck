import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';

/// 布局分析顶部工具栏，集中处理刷新、保存、展开和缩放控制。
class LayoutToolbar extends StatelessWidget {
  const LayoutToolbar({
    super.key,
    required this.hasLayout,
    required this.canSave,
    required this.showProperties,
    required this.showBorders,
    required this.enableClickSelect,
    required this.resolutionText,
    required this.onRefresh,
    required this.onSave,
    required this.onCopyXml,
    required this.onExpandAll,
    required this.onCollapseAll,
    required this.onShowPropertiesChanged,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoom1To1,
    required this.onZoomReset,
    required this.onShowBordersChanged,
    required this.onEnableClickSelectChanged,
  });

  final bool hasLayout;
  final bool canSave;
  final bool showProperties;
  final bool showBorders;
  final bool enableClickSelect;
  final String? resolutionText;
  final VoidCallback onRefresh;
  final VoidCallback onSave;
  final VoidCallback onCopyXml;
  final VoidCallback onExpandAll;
  final VoidCallback onCollapseAll;
  final ValueChanged<bool?> onShowPropertiesChanged;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoom1To1;
  final VoidCallback onZoomReset;
  final ValueChanged<bool?> onShowBordersChanged;
  final ValueChanged<bool?>? onEnableClickSelectChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
          _ToolbarButton(
            icon: Icons.refresh,
            tooltip: context.l10n.t('refreshLayout'),
            onPressed: onRefresh,
          ),
          _ToolbarButton(
            icon: Icons.save_outlined,
            tooltip: context.l10n.t('save'),
            onPressed: canSave ? onSave : null,
          ),
          _ToolbarButton(
            icon: Icons.copy_outlined,
            tooltip: context.l10n.t('copyLayout'),
            onPressed: hasLayout ? onCopyXml : null,
          ),
          const SizedBox(width: 8),
          const SizedBox(
            height: 20,
            child: VerticalDivider(width: 1, color: Colors.grey),
          ),
          const SizedBox(width: 8),
          _ToolbarButton(
            icon: Icons.unfold_more,
            tooltip: context.l10n.t('expandAll'),
            onPressed: hasLayout ? onExpandAll : null,
          ),
          _ToolbarButton(
            icon: Icons.unfold_less,
            tooltip: context.l10n.t('collapseAll'),
            onPressed: hasLayout ? onCollapseAll : null,
          ),
          const SizedBox(width: 12),
          _ToolbarCheckbox(
            label: context.l10n.t('showProperties'),
            value: showProperties,
            onChanged: onShowPropertiesChanged,
          ),
          const SizedBox(width: 8),
          const SizedBox(
            height: 20,
            child: VerticalDivider(width: 1, color: Colors.grey),
          ),
          const SizedBox(width: 8),
          _ToolbarButton(
            icon: Icons.rotate_left,
            tooltip: context.l10n.t('rotateLeft'),
            onPressed: hasLayout ? onRotateLeft : null,
          ),
          _ToolbarButton(
            icon: Icons.rotate_right,
            tooltip: context.l10n.t('rotateRight'),
            onPressed: hasLayout ? onRotateRight : null,
          ),
          _ToolbarButton(
            icon: Icons.zoom_in,
            tooltip: context.l10n.t('zoomIn'),
            onPressed: hasLayout ? onZoomIn : null,
          ),
          _ToolbarButton(
            icon: Icons.zoom_out,
            tooltip: context.l10n.t('zoomOut'),
            onPressed: hasLayout ? onZoomOut : null,
          ),
          Tooltip(
            message: context.l10n.t('zoom1to1'),
            child: InkWell(
              onTap: hasLayout ? onZoom1To1 : null,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[400]!),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '1:1',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _ToolbarButton(
            icon: Icons.settings_backup_restore,
            tooltip: context.l10n.t('zoomReset'),
            onPressed: hasLayout ? onZoomReset : null,
          ),
          const SizedBox(width: 12),
          _ToolbarCheckbox(
            label: context.l10n.t('showBorders'),
            value: showBorders,
            onChanged: onShowBordersChanged,
          ),
          const SizedBox(width: 8),
          _ToolbarCheckbox(
            label: context.l10n.t('clickToSelect'),
            value: enableClickSelect,
            onChanged: showBorders ? onEnableClickSelectChanged : null,
          ),
          const Spacer(),
          if (resolutionText != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                resolutionText!,
                style: const TextStyle(
                  color: Colors.blueGrey,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 20),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          padding: const EdgeInsets.all(6),
          minimumSize: const Size(32, 32),
        ),
      ),
    );
  }
}

class _ToolbarCheckbox extends StatelessWidget {
  const _ToolbarCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: onChanged != null ? const Color(0xff5f6368) : Colors.grey[400],
          ),
        ),
      ],
    );
  }
}
