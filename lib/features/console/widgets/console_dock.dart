import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/window/console/console_window_launcher.dart';
import '../../../app/window/console/console_window_panel.dart';
import '../controller/console_dock_controller.dart';

/// 在 [child] 工作区下方显示可调高度的日志面板，不改变当前 Route 或设备。
///
/// 用法：`ConsoleDock(child: workspace)`。关闭时释放日志视图和滚动控制器，
/// 全局 LogService 继续采集；独立窗口成功打开后才收起底部面板。
class ConsoleDock extends ConsumerStatefulWidget {
  const ConsoleDock({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ConsoleDock> createState() => _ConsoleDockState();
}

class _ConsoleDockState extends ConsumerState<ConsoleDock> {
  bool _openingWindow = false;

  Future<void> _popOut() async {
    if (_openingWindow) return;
    setState(() => _openingWindow = true);
    try {
      if (await openConsoleWindow(context) && mounted) {
        ref.read(consoleDockProvider.notifier).close();
      }
    } finally {
      if (mounted) setState(() => _openingWindow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(consoleDockProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 保留主内容操作空间，窗口缩小时限制实际高度但不覆盖用户偏好。
        final maxHeight = math.max(0.0, constraints.maxHeight - 188);
        final minHeight = math.min(140.0, maxHeight);
        final height = state.height.clamp(minHeight, maxHeight).toDouble();
        return Column(
          children: [
            Expanded(child: widget.child),
            if (state.isOpen && height >= 100) ...[
              Semantics(
                label: context.l10n.t('consoleResize'),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    key: const Key('consoleDockResizeHandle'),
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (details) {
                      final currentHeight = ref
                          .read(consoleDockProvider)
                          .height
                          .clamp(minHeight, maxHeight);
                      ref
                          .read(consoleDockProvider.notifier)
                          .resize(
                            (currentHeight - details.delta.dy)
                                .clamp(minHeight, maxHeight)
                                .toDouble(),
                          );
                    },
                    child: Container(
                      height: 8,
                      alignment: Alignment.center,
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      child: SizedBox(
                        width: 36,
                        child: Divider(
                          height: 2,
                          thickness: 2,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                key: const Key('consoleDockPanel'),
                height: height,
                // 限定毛玻璃采样范围，避免底部控制台模糊或重绘设备工作区。
                child: ClipRect(
                  child: ConsoleWindowPanel(
                    isEmbedded: true,
                    onPopOut: _openingWindow ? null : _popOut,
                    onClose: ref.read(consoleDockProvider.notifier).close,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
