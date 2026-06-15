import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/l10n/app_localizations.dart';
import '../../../../core/adb/adb_device.dart';
import '../../../../core/web_debug/webpage_target.dart';
import '../../../../core/providers/app_providers.dart';
import '../widgets/dashboard_snack.dart';

/// 网页调试标签页。

part 'webpages_table.dart';

class WebpagesTab extends ConsumerStatefulWidget {
  final AdbDevice device;
  final bool isVisible;

  const WebpagesTab({
    super.key,
    required this.device,
    required this.isVisible,
  });

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
    if (widget.isVisible) {
      _startRefreshTimer();
    }
    // 监听设备切换，自动清空选中状态
    Future.microtask(() {
      if (mounted) {
        ref.read(selectedWebTargetProvider.notifier).state = null;
      }
    });
  }

  @override
  void didUpdateWidget(covariant WebpagesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.device.id != oldWidget.device.id ||
        widget.isVisible != oldWidget.isVisible) {
      _stopRefreshTimer();
      if (widget.device.isOnline && widget.isVisible) {
        _startRefreshTimer();
      }
    }
  }

  @override
  void dispose() {
    _stopRefreshTimer();
    _filterController.dispose();
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    if (!widget.isVisible) return;
    final isOnline = ref.read(deviceOnlineProvider(widget.device.id));
    if (_autoRefresh && isOnline) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (mounted && !_refreshing) {
          final stillOnline = ref.read(deviceOnlineProvider(widget.device.id));
          if (stillOnline && widget.isVisible) {
            _refreshTargets(silent: true);
          } else {
            _stopRefreshTimer();
          }
        }
      });
    }
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
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
        DashboardSnack.show(context, e.toString(), isError: true);
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _inspectTarget() async {
    final target = _selectedTarget;
    if (target == null) return;

    final useLocal = ref.read(useLocalDebuggerProvider);
    final service = ref.read(webDebugServiceProvider);

    try {
      final latestTarget = await _resolveLatestTarget(target);
      if (latestTarget == null) {
        if (mounted) {
          DashboardSnack.show(
            context,
            context.l10n.t('webpageTargetInvalid'),
            isError: true,
          );
        }
        return;
      }
      await service.openInspector(latestTarget, useLocal);
      if (mounted) {
        DashboardSnack.show(context, context.l10n.t('attemptingStartDebugger'));
      }
    } catch (e) {
      if (mounted) {
        DashboardSnack.show(
          context,
          context.l10n
              .t('startDebuggerFailed')
              .replaceAll('{error}', e.toString()),
          isError: true,
        );
      }
    }
  }

  Future<WebpageTarget?> _resolveLatestTarget(WebpageTarget target) async {
    ref.invalidate(webTargetsProvider(widget.device.id));
    final targets = await ref.read(webTargetsProvider(widget.device.id).future);
    for (final item in targets) {
      if (item.socketName == target.socketName && item.id == target.id) {
        ref.read(selectedWebTargetProvider.notifier).state = item;
        return item;
      }
    }
    for (final item in targets) {
      if (item.socketName == target.socketName) {
        ref.read(selectedWebTargetProvider.notifier).state = item;
        return item;
      }
    }
    ref.read(selectedWebTargetProvider.notifier).state = null;
    return null;
  }

  Future<void> _openInBrowser() async {
    final target = _selectedTarget;
    if (target == null) return;

    final service = ref.read(webDebugServiceProvider);

    try {
      await service.openBrowser(target.url);
    } catch (e) {
      if (mounted) {
        DashboardSnack.show(
          context,
          context.l10n
              .t('openInBrowserFailed')
              .replaceAll('{error}', e.toString()),
          isError: true,
        );
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
    final isOnline = ref.watch(deviceOnlineProvider(widget.device.id));
    if (!isOnline) {
      _stopRefreshTimer();
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.bolt_slash, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(context.l10n.t('offlineWebpagesWarning')),
          ],
        ),
      );
    }

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
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _filterController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        CupertinoIcons.line_horizontal_3_decrease,
                        size: 16,
                      ),
                      hintText: context.l10n.t('filterWebpage'),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      suffixIcon: _filter.isNotEmpty
                          ? IconButton(
                              icon: const Icon(CupertinoIcons.clear, size: 16),
                              onPressed: () {
                                _filterController.clear();
                                setState(() => _filter = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) => setState(() => _filter = value),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
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
              IconButton(
                tooltip: context.l10n.t('refreshWebpagesTooltip'),
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.refresh, size: 20),
                onPressed: _refreshing ? null : () => _refreshTargets(),
              ),
              const SizedBox(width: 8),
              // 调试按钮 (Bug 图标)
              IconButton(
                icon: const Icon(CupertinoIcons.ant, size: 20),
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
                icon: const Icon(CupertinoIcons.globe, size: 20),
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
              loading: () => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(context.l10n.t('loadingWebpages')),
                  ],
                ),
              ),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      CupertinoIcons.exclamationmark_circle,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.l10n
                          .t('loadWebpagesFailed')
                          .replaceAll('{error}', error.toString()),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => _refreshTargets(),
                      child: Text(context.l10n.t('retry')),
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
                          CupertinoIcons.slash_circle,
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
