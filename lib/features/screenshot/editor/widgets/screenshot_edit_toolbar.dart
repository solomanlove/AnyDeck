import 'package:flutter/material.dart';

import '../../../../app/l10n/app_localizations.dart';
import '../../../../app/theme/app_theme.dart';
import '../model/screenshot_edit.dart';

/// 截图编辑工具栏：通过 state 展示工具、标注颜色、原图像素宽度及历史状态。
/// 所有修改由回调交给编辑 Controller；busy 时锁定操作，取消和完成固定在右侧，
/// 左侧工具区可横向滚动，适合嵌入截图工作台的窄窗口。
class ScreenshotEditToolbar extends StatelessWidget {
  const ScreenshotEditToolbar({
    super.key,
    required this.state,
    required this.busy,
    this.mosaicAvailable = true,
    required this.onToolChanged,
    required this.onColorChanged,
    required this.onWidthChanged,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    required this.onCancel,
    required this.onDone,
  });

  final ScreenshotEditState state;
  final bool busy;
  final bool mosaicAvailable;
  final ValueChanged<ScreenshotEditTool> onToolChanged;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onWidthChanged;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  // 标注颜色属于图片内容，不随工作台的明暗主题改变。
  static const _annotationColors = <(Color, String)>[
    (Colors.red, 'screenshotEditColorRed'),
    (Colors.yellow, 'screenshotEditColorYellow'),
    (Colors.green, 'screenshotEditColorGreen'),
    (Colors.blue, 'screenshotEditColorBlue'),
    (Colors.black, 'screenshotEditColorBlack'),
    (Colors.white, 'screenshotEditColorWhite'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final tool in ScreenshotEditTool.values)
                    _toolButton(context, tool),
                  const SizedBox(width: 12),
                  for (final (color, label) in _annotationColors)
                    _colorButton(context, color, label),
                  const SizedBox(width: 8),
                  _widthButton(context),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const ValueKey('screenshotEditUndo'),
                    tooltip: context.l10n.t('screenshotEditUndo'),
                    icon: const Icon(Icons.undo, size: 20),
                    onPressed: !busy && state.canUndo ? onUndo : null,
                  ),
                  IconButton(
                    key: const ValueKey('screenshotEditRedo'),
                    tooltip: context.l10n.t('screenshotEditRedo'),
                    icon: const Icon(Icons.redo, size: 20),
                    onPressed: !busy && state.canRedo ? onRedo : null,
                  ),
                  IconButton(
                    key: const ValueKey('screenshotEditClear'),
                    tooltip: context.l10n.t('screenshotEditClear'),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: !busy && state.isDirty ? onClear : null,
                  ),
                  Tooltip(
                    message: context.l10n.t('screenshotEditOrientationHint'),
                    child: Icon(
                      Icons.info_outline,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: const ValueKey('screenshotEditCancel'),
            onPressed: busy ? null : onCancel,
            child: Text(context.l10n.t('screenshotEditCancel')),
          ),
          const SizedBox(width: 4),
          FilledButton(
            key: const ValueKey('screenshotEditDone'),
            onPressed: busy ? null : onDone,
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.l10n.t('screenshotEditDone')),
          ),
        ],
      ),
    );
  }

  Widget _toolButton(BuildContext context, ScreenshotEditTool tool) {
    final (icon, label) = switch (tool) {
      ScreenshotEditTool.pan => (Icons.pan_tool_outlined, 'screenshotEditPan'),
      ScreenshotEditTool.rectangle => (
        Icons.crop_square,
        'screenshotEditRectangle',
      ),
      ScreenshotEditTool.ellipse => (
        Icons.radio_button_unchecked,
        'screenshotEditEllipse',
      ),
      ScreenshotEditTool.pen => (Icons.brush_outlined, 'screenshotEditPen'),
      ScreenshotEditTool.mosaic => (Icons.grid_on, 'screenshotEditMosaic'),
      ScreenshotEditTool.cover => (Icons.rectangle, 'screenshotEditCover'),
    };
    return IconButton(
      key: ValueKey('screenshotEditTool${tool.name}'),
      tooltip: context.l10n.t(label),
      icon: Icon(icon, size: 20),
      isSelected: state.tool == tool,
      style: IconButton.styleFrom(
        backgroundColor: state.tool == tool
            ? Theme.of(context).colorScheme.secondaryContainer
            : null,
        shape: const RoundedRectangleBorder(
          borderRadius: AppThemeSizes.radiusSmall,
        ),
      ),
      onPressed: busy || (tool == ScreenshotEditTool.mosaic && !mosaicAvailable)
          ? null
          : () => onToolChanged(tool),
    );
  }

  Widget _colorButton(BuildContext context, Color color, String label) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: context.l10n.t(label),
        child: InkWell(
          key: ValueKey(label),
          customBorder: const CircleBorder(),
          onTap: busy ? null : () => onColorChanged(color),
          child: Container(
            width: 30,
            height: 30,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: state.color == color ? colors.primary : colors.outline,
                width: state.color == color ? 2 : AppThemeSizes.borderWidth,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ),
        ),
      ),
    );
  }

  Widget _widthButton(BuildContext context) => PopupMenuButton<double>(
    key: const ValueKey('screenshotEditWidth'),
    enabled: !busy,
    tooltip: context.l10n.t('screenshotEditWidth'),
    initialValue: state.width,
    onSelected: onWidthChanged,
    itemBuilder: (context) => [
      for (final width in const <double>[3, 6, 12, 24, 48, 80])
        PopupMenuItem(value: width, child: Text(_widthLabel(context, width))),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.line_weight, size: 18),
          const SizedBox(width: 6),
          Text(_widthLabel(context, state.width)),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
    ),
  );

  String _widthLabel(BuildContext context, double width) => context.l10n
      .t('screenshotEditWidthValue')
      .replaceAll('{width}', width.toInt().toString());
}
