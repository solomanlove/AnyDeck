import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/adb/adb_device.dart';
import '../../../core/web_debug/webpage_target.dart';
import '../../../core/providers/app_providers.dart';

/// 网页调试标签页。
class WebpagesTab extends ConsumerStatefulWidget {
  final AdbDevice device;

  const WebpagesTab({super.key, required this.device});

  @override
  ConsumerState<WebpagesTab> createState() => _WebpagesTabState();
}

class _WebpagesTabState extends ConsumerState<WebpagesTab> {
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';
  WebpageTarget? _selectedTarget;

  Timer? _refreshTimer;
  bool _autoRefresh = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _startRefreshTimer();
    // 监听设备切换，自动清空选中状态
    Future.microtask(() {
      if (mounted) {
        ref.read(selectedWebTargetProvider.notifier).state = null;
      }
    });
  }

  @override
  void dispose() {
    _stopRefreshTimer();
    _filterController.dispose();
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    if (_autoRefresh) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (mounted && !_refreshing) {
          _refreshTargets(silent: true);
        }
      });
    }
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
  }

  void _toggleAutoRefresh(bool? value) {
    if (value == null) return;
    setState(() {
      _autoRefresh = value;
      if (_autoRefresh) {
        _startRefreshTimer();
      } else {
        _stopRefreshTimer();
      }
    });
  }

  Future<void> _refreshTargets({bool silent = false}) async {
    if (_refreshing) return;
    if (!silent) {
      setState(() => _refreshing = true);
    }
    try {
      ref.invalidate(webTargetsProvider(widget.device.id));
      await ref.read(webTargetsProvider(widget.device.id).future);
    } catch (e) {
      if (mounted && !silent) {
        _showSnack(context, e.toString(), isError: true);
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _refreshing = false);
      }
    }
  }

  void _showSnack(BuildContext context, String message, {bool isError = false}) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final media = MediaQuery.of(context);
    final accentColor = isError
        ? Theme.of(context).colorScheme.error
        : const Color(0xff00c853);
    final textStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: const Color(0xff171a21),
      fontWeight: FontWeight.w600,
    );

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: media.padding.top + 16,
          left: 16,
          right: 16,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: media.size.width - 64),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xffd7dce5)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isError ? Icons.error : Icons.check_circle,
                          color: accentColor,
                          size: 30,
                        ),
                        const SizedBox(width: 12),
                        Flexible(child: Text(message, style: textStyle)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    Timer(const Duration(seconds: 2), () {
      if (entry.mounted) {
        entry.remove();
      }
    });
  }

  Future<void> _inspectTarget() async {
    final target = _selectedTarget;
    if (target == null) return;

    final useLocal = ref.read(useLocalDebuggerProvider);
    final service = ref.read(webDebugServiceProvider);

    try {
      await service.openInspector(target, useLocal);
      if (mounted) {
        _showSnack(context, '正在尝试开启调试器...');
      }
    } catch (e) {
      if (mounted) {
        _showSnack(context, '启动调试器失败: $e', isError: true);
      }
    }
  }

  Future<void> _openInBrowser() async {
    final target = _selectedTarget;
    if (target == null) return;

    final service = ref.read(webDebugServiceProvider);

    try {
      await service.openBrowser(target.url);
    } catch (e) {
      if (mounted) {
        _showSnack(context, '在浏览器中打开链接失败: $e', isError: true);
      }
    }
  }

  List<WebpageTarget> _filterTargets(List<WebpageTarget> items) {
    final query = _filter.trim().toLowerCase();
    if (query.isEmpty) return items;
    return items.where((item) {
      return item.title.toLowerCase().contains(query) ||
          item.url.toLowerCase().contains(query) ||
          item.type.toLowerCase().contains(query) ||
          item.packageName.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final targetsAsync = ref.watch(webTargetsProvider(widget.device.id));
    final useLocalDebugger = ref.watch(useLocalDebuggerProvider);

    // 同步选中的网页目标状态
    _selectedTarget = ref.watch(selectedWebTargetProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 顶部操作栏
          Row(
            children: [
              Expanded(
                flex: 4,
                child: TextField(
                  controller: _filterController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: context.l10n.t('filterWebpage'),
                    suffixIcon: _filter.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _filterController.clear();
                              setState(() => _filter = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) => setState(() => _filter = value),
                ),
              ),
              const SizedBox(width: 12),
              // 展示当前选中目标的 Title
              Expanded(
                flex: 3,
                child: Text(
                  _selectedTarget != null
                      ? _selectedTarget!.title.isNotEmpty
                          ? _selectedTarget!.title
                          : _selectedTarget!.url
                      : '',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              // 自动刷新
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _autoRefresh,
                    onChanged: _toggleAutoRefresh,
                  ),
                  const Text('自动刷新 (5s)'),
                ],
              ),
              const SizedBox(width: 8),
              // 使用本地调试器 Checkbox
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: useLocalDebugger,
                    onChanged: (_) =>
                        ref.read(useLocalDebuggerProvider.notifier).toggle(),
                  ),
                  Text(context.l10n.t('useLocalDebugger')),
                ],
              ),
              const SizedBox(width: 12),
              // 刷新按钮
              IconButton.filledTonal(
                tooltip: '手动刷新网页列表',
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onPressed: _refreshing ? null : () => _refreshTargets(),
              ),
              const SizedBox(width: 8),
              // 调试按钮 (Bug 图标)
              IconButton(
                icon: const Icon(Icons.bug_report),
                style: IconButton.styleFrom(
                  backgroundColor: _selectedTarget != null
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  foregroundColor: _selectedTarget != null
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : null,
                ),
                tooltip: context.l10n.t('inspectWebpage'),
                onPressed: _selectedTarget != null ? _inspectTarget : null,
              ),
              const SizedBox(width: 8),
              // 浏览器打开按钮 (Globe 图标)
              IconButton(
                icon: const Icon(Icons.language),
                style: IconButton.styleFrom(
                  backgroundColor: _selectedTarget != null
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : null,
                  foregroundColor: _selectedTarget != null
                      ? Theme.of(context).colorScheme.onSecondaryContainer
                      : null,
                ),
                tooltip: context.l10n.t('openInBrowser'),
                onPressed: _selectedTarget != null ? _openInBrowser : null,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 网页列表表格
          Expanded(
            child: targetsAsync.when(
              loading: () => const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在加载手机网页调试目标...'),
                  ],
                ),
              ),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('加载网页列表失败: $error'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => _refreshTargets(),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
              data: (items) {
                final filtered = _filterTargets(items);

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.web_asset_off_outlined,
                            size: 48, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(context.l10n.t('noWebpages')),
                      ],
                    ),
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final widths = _WebpageTableWidths.adaptive(
                      viewportWidth: constraints.maxWidth,
                    );

                    return _WebpageTable(
                      targets: filtered,
                      selectedId: _selectedTarget?.id,
                      widths: widths,
                      onSelected: (target) {
                        final current = ref.read(selectedWebTargetProvider);
                        if (current?.id == target.id) {
                          ref.read(selectedWebTargetProvider.notifier).state = null;
                        } else {
                          ref.read(selectedWebTargetProvider.notifier).state = target;
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WebpageTableWidths {
  final double title;
  final double url;
  final double type;

  const _WebpageTableWidths({
    required this.title,
    required this.url,
    required this.type,
  });

  factory _WebpageTableWidths.adaptive({required double viewportWidth}) {
    const double minTotal = 700.0;
    if (viewportWidth > minTotal) {
      final double extra = viewportWidth - minTotal;
      return _WebpageTableWidths(
        title: 250.0 + extra * 0.4,
        url: 350.0 + extra * 0.6,
        type: 100.0,
      );
    } else {
      return const _WebpageTableWidths(
        title: 250.0,
        url: 350.0,
        type: 100.0,
      );
    }
  }

  double get total => title + url + type;
}

class _WebpageTable extends StatefulWidget {
  final List<WebpageTarget> targets;
  final String? selectedId;
  final _WebpageTableWidths widths;
  final ValueChanged<WebpageTarget> onSelected;

  const _WebpageTable({
    required this.targets,
    required this.selectedId,
    required this.widths,
    required this.onSelected,
  });

  @override
  State<_WebpageTable> createState() => _WebpageTableState();
}

class _WebpageTableState extends State<_WebpageTable> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tableWidth = widget.widths.total;

    return Scrollbar(
      controller: _horizontalController,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _horizontalController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          child: Column(
            children: [
              // 表头
              _buildTableHeader(context),
              // 数据行
              Expanded(
                child: Scrollbar(
                  controller: _verticalController,
                  child: ListView.builder(
                    controller: _verticalController,
                    itemCount: widget.targets.length,
                    itemBuilder: (context, index) {
                      final target = widget.targets[index];
                      return _buildTableRow(context, target, index);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final headerStyle = textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    Widget headerCell(String label, double width) {
      return Container(
        width: width,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: headerStyle,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          headerCell(context.l10n.t('webpageTitle'), widget.widths.title),
          headerCell(context.l10n.t('webpageUrl'), widget.widths.url),
          headerCell(context.l10n.t('webpageType'), widget.widths.type),
        ],
      ),
    );
  }

  Widget _buildTableRow(BuildContext context, WebpageTarget target, int index) {
    final isSelected = target.id == widget.selectedId;

    // 行背景交替色
    final Color? rowColor = isSelected
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
        : index % 2 == 0
            ? null
            : Theme.of(context)
                .colorScheme
                .surfaceContainerLowest
                .withValues(alpha: 0.5);

    return InkWell(
      onTap: () => widget.onSelected(target),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: rowColor,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // 标题
            Container(
              width: widget.widths.title,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    target.title.isNotEmpty ? target.title : '无标题',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${target.packageName} (PID: ${target.pid})',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // URL
            Container(
              width: widget.widths.url,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              child: Text(
                target.url,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 类型
            Container(
              width: widget.widths.type,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              child: Chip(
                label: Text(
                  target.type,
                  style: const TextStyle(fontSize: 11),
                ),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
