import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:glassmorphism/glassmorphism.dart';

import '../../l10n/app_localizations.dart';
import '../../../core/logging/log_service.dart';

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
  TextSpan _buildLogSpan(String line, bool isDark) {
    // 匹配类似: "15:50:31.722 I adb: init"
    final match = RegExp(
      r'^(\d{2}:\d{2}:\d{2}\.\d{3})\s+([IWE])\s+(.*?)$',
    ).firstMatch(line);
    final TextStyle defaultStyle = TextStyle(
      fontFamily: Platform.isMacOS ? 'Menlo' : 'Consolas',
      fontSize: 12.0,
      height: 1.4,
      color: isDark ? const Color(0xffe0e0e0) : const Color(0xff2d2d2d),
    );

    if (match == null) {
      return TextSpan(text: '$line\n', style: defaultStyle);
    }

    final time = match.group(1)!;
    final level = match.group(2)!;
    final content = match.group(3)!;

    final Color levelColor = switch (level) {
      'E' => const Color(0xfff44336), // 红色错误
      'W' => const Color(0xffffb300), // 橙色警告
      _ => isDark ? const Color(0xff00e676) : const Color(0xff2e7d32), // 绿色信息
    };

    return TextSpan(
      style: defaultStyle,
      children: [
        TextSpan(
          text: '$time ',
          style: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600]),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logs = ref.watch(logHistoryProvider);

    // 过滤日志
    final filteredLogs = logs.where((log) {
      if (_hideHeartbeats && _isHeartbeat(log)) {
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
    final glassBgColor = isDark
        ? Colors.black.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.28);
    final terminalBgColor = isDark
        ? const Color(0xff0d0e15)
        : const Color(0xfff5f6fa);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: Container(
        color: glassBgColor,
        child: Column(
          children: [
            // 自定义顶部标题与操作栏，内置 DragToMoveArea 支持窗口拖拽
            DragToMoveArea(
              child: GlassmorphicContainer(
                width: double.infinity,
                height: 50,
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
                  child: Row(
                    children: [
                      Text(
                        context.l10n.t('console'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xffeceff1)
                                  : const Color(0xff202124),
                            ),
                      ),
                      const SizedBox(width: 16),
                      // 搜索输入框
                      SizedBox(
                        width: 150,
                        height: 28,
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: context.l10n.t('searchLogsHint'),
                            hintStyle: TextStyle(
                              color: isDark
                                  ? Colors.grey[600]
                                  : Colors.grey[400],
                              fontSize: 12,
                            ),
                            prefixIcon: const Icon(
                              CupertinoIcons.search,
                              size: 14,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 0,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            fillColor: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.04),
                            filled: true,
                          ),
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val.trim().toLowerCase();
                            });
                          },
                        ),
                      ),
                      const Spacer(),
                      // 隐藏心跳配置
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _hideHeartbeats,
                            onChanged: (val) {
                              setState(() {
                                _hideHeartbeats = val ?? true;
                              });
                            },
                          ),
                          Text(
                            context.l10n.t('hideHeartbeats'),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.grey[300]
                                  : Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      // 自动滚动配置
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _autoScroll,
                            onChanged: (val) {
                              setState(() {
                                _autoScroll = val ?? true;
                              });
                            },
                          ),
                          Text(
                            context.l10n.t('autoScroll'),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.grey[300]
                                  : Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      // 复制日志按钮
                      IconButton(
                        tooltip: context.l10n.t('copyAll'),
                        icon: const Icon(CupertinoIcons.doc_on_doc, size: 18),
                        onPressed: () => _copyAllLogs(filteredLogs),
                      ),
                      // 清空日志按钮
                      IconButton(
                        tooltip: context.l10n.t('clear'),
                        icon: const Icon(CupertinoIcons.trash, size: 18),
                        onPressed: () {
                          ref.read(logHistoryProvider.notifier).clear();
                        },
                      ),
                    ],
                  ),
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
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    width: 1,
                  ),
                ),
                child: Scrollbar(
                  controller: _scrollController,
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: filteredLogs.length,
                    itemBuilder: (context, index) {
                      return SelectionArea(
                        child: Text.rich(
                          _buildLogSpan(filteredLogs[index], isDark),
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
