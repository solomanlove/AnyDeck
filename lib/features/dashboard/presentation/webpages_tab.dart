import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/adb/adb_device.dart';
import '../../../core/web_debug/webpage_target.dart';
import '../../../core/providers/app_providers.dart';

/// 网页调试标签页。

part 'webpages_table.dart';

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

  void _showSnack(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
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
                  Checkbox(value: _autoRefresh, onChanged: _toggleAutoRefresh),
                  Text(
                    context.l10n
                        .t('autoRefreshInterval')
                        .replaceAll('{seconds}', '5'),
                  ),
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
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
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
                        const Icon(
                          Icons.web_asset_off_outlined,
                          size: 48,
                          color: Colors.grey,
                        ),
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
                          ref.read(selectedWebTargetProvider.notifier).state =
                              null;
                        } else {
                          ref.read(selectedWebTargetProvider.notifier).state =
                              target;
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
