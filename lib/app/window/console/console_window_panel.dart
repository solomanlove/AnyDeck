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
                          height: 32,
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
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              fillColor: theme.colorScheme.onSurface.withValues(
                                alpha: 0.05,
                              ),
                              filled: true,
                            ),
                            onChanged: (value) => setState(
                              () => _searchQuery = value.trim().toLowerCase(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Tooltip(
                          message: context.l10n.t('consoleKeyLogs'),
                          child: FilterChip(
                            key: const Key('consoleKeyLogsFilter'),
                            avatar: compact
                                ? const Icon(
                                    Icons.filter_alt_outlined,
                                    size: 16,
                                  )
                                : null,
                            label: compact
                                ? const SizedBox.shrink()
                                : Text(context.l10n.t('consoleKeyLogs')),
                            selected: _keyLogsOnly,
                            onSelected: (value) =>
                                setState(() => _keyLogsOnly = value),
                          ),
                        ),
                        const SizedBox(width: 8),
                        LocalLogCaptureButton(iconOnly: compact),
                        const Spacer(),
                        _ConsoleToggle(
                          label: context.l10n.t('hideHeartbeats'),
                          value: _hideHeartbeats,
                          compact: compact,
                          onChanged: (value) =>
                              setState(() => _hideHeartbeats = value ?? true),
                        ),
                        _ConsoleToggle(
                          label: context.l10n.t('autoScroll'),
                          value: _autoScroll,
                          compact: compact,
                          onChanged: (value) =>
                              setState(() => _autoScroll = value ?? true),
                        ),
                        IconButton(
                          tooltip: context.l10n.t('copyAll'),
                          icon: const Icon(CupertinoIcons.doc_on_doc, size: 18),
                          onPressed: () => _copyAllLogs(filteredLogs),
                        ),
                        IconButton(
                          tooltip: context.l10n.t('clear'),
                          icon: const Icon(CupertinoIcons.trash, size: 18),
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

/// 空间不足时仅保留 Checkbox，并通过 Tooltip 暴露完整配置名称。
class _ConsoleToggle extends StatelessWidget {
  const _ConsoleToggle({
    required this.label,
    required this.value,
    required this.compact,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool compact;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(value: value, onChanged: onChanged),
          if (!compact)
            Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
