import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/adb/adb_device.dart';
import '../model/screenshot_state.dart';

/// 截图与布局分析共享控制工具栏。
/// 左侧和中间操作按钮区支持横向滚动（保证窄窗口下不溢出）；
/// 右侧固化显示分辨率/大小信息以及 Android 专属的“布局分析”模式开关。
class ScreenshotToolbar extends StatelessWidget {
  const ScreenshotToolbar({
    super.key,
    required this.device,
    required this.state,
    required this.onRefresh,
    required this.onSave,
    required this.onCopy,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoom1To1,
    required this.onZoomReset,
    required this.onToggleAutoRefresh,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onToggleLayoutAnalysis,
    required this.onExpandAll,
    required this.onCollapseAll,
    required this.onShowPropertiesChanged,
    required this.onShowBordersChanged,
    required this.onUseDpChanged,
  });

  final AdbDevice device;
  final ScreenshotLayoutState state;

  final VoidCallback onRefresh;
  final VoidCallback onSave;
  final VoidCallback onCopy;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoom1To1;
  final VoidCallback onZoomReset;
  final VoidCallback onToggleAutoRefresh;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final ValueChanged<bool> onToggleLayoutAnalysis;
  final VoidCallback onExpandAll;
  final VoidCallback onCollapseAll;
  final ValueChanged<bool?> onShowPropertiesChanged;
  final ValueChanged<bool?> onShowBordersChanged;
  final ValueChanged<bool?> onUseDpChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final hasImage = state.hasImage;
    final isRecActive = state.isRecordingActive;
    final isAnalysis = state.isLayoutAnalysis;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff1f2937) : const Color(0xfff7f9fa),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          // 左侧与中部功能按钮区：支持横向平滑滚动，避免窗口缩小时产生 RenderFlex 溢出
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. 刷新按钮
                  _ToolbarButton(
                    icon: CupertinoIcons.refresh,
                    tooltip: isAnalysis
                        ? context.l10n.t('refreshLayoutAndScreenshot')
                        : context.l10n.t('refresh'),
                    onPressed: (state.isLoading || isRecActive) ? null : onRefresh,
                  ),
                  // 2. 保存按钮（普通模式保存图片，分析模式保存图片+XML）
                  _ToolbarButton(
                    icon: CupertinoIcons.floppy_disk,
                    tooltip: isAnalysis
                        ? context.l10n.t('exportPngAndXml')
                        : context.l10n.t('save'),
                    onPressed: (!hasImage || isRecActive) ? null : onSave,
                  ),
                  // 3. 复制按钮（普通模式复制图片，分析模式复制 XML）
                  _ToolbarButton(
                    icon: CupertinoIcons.doc_on_doc,
                    tooltip: isAnalysis
                        ? context.l10n.t('copyLayout')
                        : context.l10n.t('copy'),
                    onPressed: (!hasImage || isRecActive) ? null : onCopy,
                  ),
                  _buildDivider(isDark),
                  // 4. 旋转控制
                  _ToolbarButton(
                    icon: CupertinoIcons.rotate_left,
                    tooltip: context.l10n.t('rotateLeft'),
                    onPressed: (!hasImage || isRecActive) ? null : onRotateLeft,
                  ),
                  _ToolbarButton(
                    icon: CupertinoIcons.rotate_right,
                    tooltip: context.l10n.t('rotateRight'),
                    onPressed: (!hasImage || isRecActive) ? null : onRotateRight,
                  ),
                  _buildDivider(isDark),
                  // 5. 缩放控制
                  _ToolbarButton(
                    icon: CupertinoIcons.zoom_in,
                    tooltip: context.l10n.t('zoomIn'),
                    onPressed: (!hasImage || isRecActive) ? null : onZoomIn,
                  ),
                  _ToolbarButton(
                    icon: CupertinoIcons.zoom_out,
                    tooltip: context.l10n.t('zoomOut'),
                    onPressed: (!hasImage || isRecActive) ? null : onZoomOut,
                  ),
                  _buildZoom1to1Button(context, isDark, hasImage && !isRecActive),
                  const SizedBox(width: 6),
                  _ToolbarButton(
                    icon: CupertinoIcons.arrow_counterclockwise,
                    tooltip: context.l10n.t('zoomReset'),
                    onPressed: (!hasImage || isRecActive) ? null : onZoomReset,
                  ),
                  // 6. 普通模式专属：连续截图与录屏
                  if (!isAnalysis) ...[
                    _buildDivider(isDark),
                    _ToolbarButton(
                      icon: CupertinoIcons.clock,
                      tooltip: context.l10n.t('autoRefresh'),
                      color: state.isAutoRefresh ? colorScheme.primary : null,
                      onPressed: (!hasImage || isRecActive) ? null : onToggleAutoRefresh,
                    ),
                    if (!device.isIos) ...[
                      _buildDivider(isDark),
                      _ToolbarButton(
                        icon: state.recordPhase == ScreenRecordPhase.recording
                            ? CupertinoIcons.stop
                            : CupertinoIcons.videocam,
                        tooltip: state.recordPhase == ScreenRecordPhase.recording
                            ? context.l10n.t('stopRecord')
                            : context.l10n.t('startRecord'),
                        color: state.recordPhase == ScreenRecordPhase.recording
                            ? Colors.red
                            : null,
                        onPressed: state.isLoading ||
                                state.recordPhase == ScreenRecordPhase.starting ||
                                state.recordPhase == ScreenRecordPhase.stopping ||
                                state.recordPhase == ScreenRecordPhase.saving
                            ? null
                            : (state.recordPhase == ScreenRecordPhase.recording
                                ? onStopRecording
                                : onStartRecording),
                      ),
                      if (state.recordPhase == ScreenRecordPhase.recording) ...[
                        const SizedBox(width: 8),
                        const _PulsingRecordDot(),
                        const SizedBox(width: 6),
                        Text(
                          _formatDuration(state.recordDuration),
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ],
                  // 7. 布局分析模式专属：展开折叠、边框显示、点击选中、DP 单位、属性面板
                  if (isAnalysis) ...[
                    _buildDivider(isDark),
                    _ToolbarButton(
                      icon: CupertinoIcons.chevron_up_chevron_down,
                      tooltip: context.l10n.t('expandAll'),
                      onPressed: state.rootNode != null ? onExpandAll : null,
                    ),
                    _ToolbarButton(
                      icon: CupertinoIcons.minus,
                      tooltip: context.l10n.t('collapseAll'),
                      onPressed: state.rootNode != null ? onCollapseAll : null,
                    ),
                    const SizedBox(width: 8),
                    _ToolbarCheckbox(
                      label: context.l10n.t('showProperties'),
                      value: state.showProperties,
                      onChanged: onShowPropertiesChanged,
                    ),
                    const SizedBox(width: 8),
                    _ToolbarCheckbox(
                      label: context.l10n.t('showBorders'),
                      value: state.showBorders,
                      onChanged: onShowBordersChanged,
                    ),
                    const SizedBox(width: 8),
                    _ToolbarCheckbox(
                      label: 'DP',
                      value: state.useDp,
                      onChanged: onUseDpChanged,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
          // 右侧固定区域：分辨率大小与“布局分析”开关（固定可见）
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasImage)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    '${state.imgWidth}x${state.imgHeight} PNG ${state.sizeLabel}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              // 仅 Android 设备显示“布局分析”开关，iOS 与 HarmonyOS 保持现有截图能力并不展示开关
              if (!device.isIos && !device.isHarmony) ...[
                _buildDivider(isDark),
                _buildLayoutAnalysisToggle(context, isDark),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      height: 20,
      child: VerticalDivider(
        width: 1,
        color: isDark ? Colors.grey[700] : Colors.grey[300],
      ),
    );
  }

  Widget _buildZoom1to1Button(BuildContext context, bool isDark, bool enabled) {
    return Tooltip(
      message: context.l10n.t('zoom1to1'),
      child: InkWell(
        onTap: enabled ? onZoom1To1 : null,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: enabled
                  ? (isDark ? Colors.grey[600]! : Colors.grey[400]!)
                  : (isDark ? Colors.grey[800]! : Colors.grey[300]!),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '1:1',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: enabled
                  ? (isDark ? Colors.grey[300] : Colors.blueGrey)
                  : (isDark ? Colors.grey[700] : Colors.grey[400]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLayoutAnalysisToggle(BuildContext context, bool isDark) {
    final canToggle = state.canToggleLayoutAnalysis;
    final tooltipMsg = state.cannotToggleReasonKey != null
        ? context.l10n.t(state.cannotToggleReasonKey!)
        : context.l10n.t('layoutAnalysisTooltip');

    final activeColor = Theme.of(context).colorScheme.primary;

    return Tooltip(
      message: tooltipMsg,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.square_stack_3d_up,
            size: 16,
            color: canToggle
                ? (state.isLayoutAnalysis ? activeColor : (isDark ? Colors.grey[300] : Colors.grey[700]))
                : Colors.grey,
          ),
          const SizedBox(width: 6),
          Text(
            context.l10n.t('layoutAnalysis'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: canToggle
                  ? (state.isLayoutAnalysis ? activeColor : (isDark ? Colors.grey[300] : Colors.grey[800]))
                  : Colors.grey,
            ),
          ),
          const SizedBox(width: 4),
          Transform.scale(
            scale: 0.75,
            child: CupertinoSwitch(
              value: state.isLayoutAnalysis,
              activeTrackColor: activeColor,
              onChanged: canToggle ? onToggleLayoutAnalysis : null,
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
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 20, color: color),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: onChanged != null
                ? (isDark ? Colors.grey[300] : const Color(0xff5f6368))
                : (isDark ? Colors.grey[600] : Colors.grey[400]),
          ),
        ),
      ],
    );
  }
}

class _PulsingRecordDot extends StatefulWidget {
  const _PulsingRecordDot();

  @override
  State<_PulsingRecordDot> createState() => _PulsingRecordDotState();
}

class _PulsingRecordDotState extends State<_PulsingRecordDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

String _formatDuration(int seconds) {
  final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
  final secs = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$secs';
}
