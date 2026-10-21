import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:glassmorphism/glassmorphism.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../../core/logging/log_service.dart';
import '../../../core/logging/app_log_recorder.dart';
import '../../widget/local_log_capture_button.dart';

/// 将 ISO 8601 时间转换为控制台使用的可读格式，不改变底层日志内容。
String formatConsoleTimestamp(String timestamp) =>
    timestamp.replaceFirst('T', ' ');

/// 控制台独立窗口的 UI 内容组件。
class ConsoleWindowPanel extends ConsumerStatefulWidget {
  const ConsoleWindowPanel({super.key});

  @override
  ConsumerState<ConsoleWindowPanel> createState() => _ConsoleWindowPanelState();
}

class _ConsoleWindowPanelState extends ConsumerState<ConsoleWindowPanel> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  /// 是否自动滚动到最底部
  bool _autoScroll = true;

  /// 是否隐藏心跳/周期性轮询命令
  bool _hideHeartbeats = true;

  /// 当前搜索关键字
  String _searchQuery = '';

  /// 聚焦警告和错误；与关键词筛选共同生效。
  bool _keyLogsOnly = false;

  @override
  void initState() {
    super.initState();
    // 启动时同步主 Isolate 已记录的历史日志
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(logHistoryProvider.notifier).syncHistory();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 过滤命令是否是心跳/周期性轮询（例如 devices -l，dumpsys cpuinfo，top，ps等）
  bool _isHeartbeat(String line) {
    final l = line.toLowerCase();
    return l.contains('devices -l') ||
        l.contains('dumpsys cpuinfo') ||
        l.contains('dumpsys meminfo') ||
        l.contains('top -b -n 1') ||
        l.contains('ps -ef') ||
        l.contains('ps -w') ||
        l.contains('getprop sys.power') ||
        l.contains('screencap -p');
  }

  /// 复制当前过滤后的全部日志到剪贴板
  void _copyAllLogs(List<String> filteredLogs) {
    final text = filteredLogs.join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.t('copySuccess')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 构建带语法高亮的单条日志 TextSpan
  TextSpan _buildLogSpan(String line, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    // 支持带日期的运行记录与旧版时间格式，异常堆栈保留为同一条日志。
    final match = RegExp(r'^(\S+)\s+([VDIWEF])\s+([\s\S]*)$').firstMatch(line);
    final TextStyle defaultStyle = TextStyle(
      fontFamily: Platform.isMacOS ? 'Menlo' : 'Consolas',
      fontSize: 12.0,
      height: 1.4,
      color: theme.colorScheme.onSurface,
    );

    if (match == null) {
      return TextSpan(text: '$line\n', style: defaultStyle);
    }

    final time = formatConsoleTimestamp(match.group(1)!);
    final level = match.group(2)!;
    final content = match.group(3)!;

    final Color levelColor = switch (level) {
      'E' || 'F' => const Color(0xfff44336), // 红色错误
      'W' => const Color(0xffffb300), // 橙色警告
      _ => isDark ? const Color(0xff00e676) : const Color(0xff2e7d32), // 绿色信息
    };

    return TextSpan(
      style: defaultStyle,
      children: [
        TextSpan(
          text: '$time ',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        TextSpan(
          text: '$level ',
          style: TextStyle(color: levelColor, fontWeight: FontWeight.bold),
        ),
        TextSpan(text: '$content\n'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final logs = ref.watch(logHistoryProvider);

    // 过滤日志
    final filteredLogs = logs.where((log) {
      final isKey = AppLogRecorder.isKeyLog(log);
      if (_keyLogsOnly && !isKey) return false;
      if (_hideHeartbeats && !isKey && _isHeartbeat(log)) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        return log.toLowerCase().contains(_searchQuery);
      }
      return true;
    }).toList();

    // 当日志增加时，如果开启了自动滚动，则滑动到最底下
    ref.listen<List<String>>(logHistoryProvider, (prev, next) {
      if (_autoScroll && _scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });

    // 磨砂玻璃色调配置
    final glassBgColor = theme.appColors.glassSurface;
    final terminalBgColor = theme.appColors.sunkenSurface;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: Container(
        color: glassBgColor,
        child: Column(
          children: [
            // 自定义顶部标题与操作栏，仅标题区域参与窗口拖拽，避免拦截控件点击。
            GlassmorphicContainer(
              width: double.infinity,
              height: 64,
              borderRadius: 0,
              blur: 15,
              alignment: Alignment.center,
              border: 0,
              linearGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.white.withValues(alpha: 0.40),
                  isDark
                      ? Colors.white.withValues(alpha: 0.01)
                      : Colors.white.withValues(alpha: 0.15),
                ],
              ),
              borderGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.04),
                  isDark
                      ? Colors.white.withValues(alpha: 0.03)
                      : Colors.black.withValues(alpha: 0.02),
                ],
              ),
              child: Container(
                padding: EdgeInsets.only(
                  left: Platform.isMacOS ? 80 : 20,
                  right: 20,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.03),
                      width: 1,
                    ),
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 1280;
                    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    );
                    final toolbarButtonStyle = _consoleToolbarButtonStyle(
                      theme,
                    );
                    return Row(
                      children: [
                        DragToMoveArea(
                          child: SizedBox(
                            width: compact ? 170 : 230,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.t('console'),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  context.l10n.t('consoleDescription'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: secondaryStyle,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: compact ? 130 : 180,
                          height: 36,
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              hintText: context.l10n.t('searchLogsHint'),
                              prefixIcon: const Icon(
                                CupertinoIcons.search,
                                size: 14,
                              ),
                              contentPadding: EdgeInsets.zero,
                              border: OutlineInputBorder(
                                borderRadius: AppThemeSizes.radiusMedium,
                                borderSide: BorderSide(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: AppThemeSizes.radiusMedium,
                                borderSide: BorderSide(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                              fillColor: theme.appColors.subtleSurface,
                              filled: true,
                            ),
                            onChanged: (value) => setState(
                              () => _searchQuery = value.trim().toLowerCase(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ConsoleToolbarButton(
                          key: const Key('consoleKeyLogsFilter'),
                          tooltip: context.l10n.t('consoleKeyLogs'),
                          icon: Icons.filter_alt_outlined,
                          selected: _keyLogsOnly,
                          onPressed: () =>
                              setState(() => _keyLogsOnly = !_keyLogsOnly),
                        ),
                        const SizedBox(width: 8),
                        LocalLogCaptureButton(
                          iconOnly: true,
                          iconButtonStyle: toolbarButtonStyle,
                        ),
                        const Spacer(),
                        _ConsoleToolbarButton(
                          tooltip: context.l10n.t('hideHeartbeats'),
                          icon: Icons.monitor_heart_outlined,
                          selected: _hideHeartbeats,
                          onPressed: () => setState(
                            () => _hideHeartbeats = !_hideHeartbeats,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ConsoleToolbarButton(
                          tooltip: context.l10n.t('autoScroll'),
                          icon: Icons.vertical_align_bottom_rounded,
                          selected: _autoScroll,
                          onPressed: () =>
                              setState(() => _autoScroll = !_autoScroll),
                        ),
                        const SizedBox(width: 8),
                        _ConsoleToolbarButton(
                          tooltip: context.l10n.t('copyAll'),
                          icon: CupertinoIcons.doc_on_doc,
                          onPressed: () => _copyAllLogs(filteredLogs),
                        ),
                        const SizedBox(width: 8),
                        _ConsoleToolbarButton(
                          tooltip: context.l10n.t('clear'),
                          icon: CupertinoIcons.trash,
                          onPressed: () =>
                              ref.read(logHistoryProvider.notifier).clear(),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            // 日志文本显示终端区域
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: terminalBgColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.appColors.subtleDivider,
                    width: 1,
                  ),
                ),
                child: filteredLogs.isEmpty
                    ? Center(child: Text(context.l10n.t('consoleNoLogs')))
                    : Scrollbar(
                        controller: _scrollController,
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: filteredLogs.length,
                          itemBuilder: (context, index) {
                            return SelectionArea(
                              child: Text.rich(
                                _buildLogSpan(filteredLogs[index], theme),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 控制台 Toolbar 的统一 Icon 操作，选中态使用主题主色表达开关状态。
class _ConsoleToolbarButton extends StatelessWidget {
  const _ConsoleToolbarButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      tooltip: tooltip,
      isSelected: selected,
      style: _consoleToolbarButtonStyle(theme, selected: selected),
      icon: Icon(icon, size: 18),
      selectedIcon: Icon(icon, size: 18),
      onPressed: onPressed,
    );
  }
}

ButtonStyle _consoleToolbarButtonStyle(
  ThemeData theme, {
  bool selected = false,
}) {
  return IconButton.styleFrom(
    minimumSize: const Size.square(36),
    maximumSize: const Size.square(36),
    padding: EdgeInsets.zero,
    foregroundColor: selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant,
    backgroundColor: selected
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : theme.appColors.subtleSurface,
    side: BorderSide(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.35)
          : theme.colorScheme.outlineVariant,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: AppThemeSizes.radiusMedium,
    ),
  );
}
