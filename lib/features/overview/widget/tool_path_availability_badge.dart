import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_colors.dart';
import '../../../app/theme/app_theme_sizes.dart';
import '../../../core/process/tool_path_settings.dart';

/// 在已应用的 CLI 路径不可用时显示黄色标识，不运行工具做版本探测。
///
/// [toolName] 对应核心依赖的设置键；[resolvedPath] 必须取当前实际执行路径，
/// 不能使用输入框草稿。[revision] 变化或应用恢复前台时重新检查，方便安装后刷新。
/// [builder] 可将同一检测结果用于其他控件：null 表示检测中，第三个参数为徽标。
/// 用法：`ToolPathAvailabilityBadge(toolName: 'hdc', resolvedPath: path)`。
class ToolPathAvailabilityBadge extends StatefulWidget {
  const ToolPathAvailabilityBadge({
    super.key,
    required this.toolName,
    required this.resolvedPath,
    this.revision = 0,
    this.builder,
  });

  final String toolName;
  final String resolvedPath;
  final int revision;
  final Widget Function(BuildContext context, bool? available, Widget badge)?
  builder;

  @override
  State<ToolPathAvailabilityBadge> createState() =>
      _ToolPathAvailabilityBadgeState();
}

class _ToolPathAvailabilityBadgeState extends State<ToolPathAvailabilityBadge>
    with WidgetsBindingObserver {
  late Future<bool> _available;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void didUpdateWidget(covariant ToolPathAvailabilityBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.toolName != oldWidget.toolName ||
        widget.resolvedPath != oldWidget.resolvedPath ||
        widget.revision != oldWidget.revision) {
      _check();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(_check);
  }

  void _check() {
    _available = isToolPathAvailable(widget.toolName, widget.resolvedPath);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _available,
    builder: (context, snapshot) {
      // 新路径检查完成前不沿用旧结果，徽标和目录按钮同步反映当前检测状态。
      final available = snapshot.connectionState == ConnectionState.done
          ? snapshot.data == true
          : null;
      final badge = _buildBadge(context, available);
      return widget.builder?.call(context, available, badge) ?? badge;
    },
  );

  Widget _buildBadge(BuildContext context, bool? available) {
    if (available != false) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final foreground = theme.environmentWarningForeground;
    return Tooltip(
      message: context.l10n.t('toolPathUnavailableHint'),
      child: Container(
        key: ValueKey('tool-unavailable-${widget.toolName}'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.environmentWarningBackground,
          borderRadius: AppThemeSizes.radiusSmall,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 16, color: foreground),
            const SizedBox(width: 4),
            Text(
              context.l10n.t('toolPathUnavailable'),
              style: theme.textTheme.labelSmall?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
