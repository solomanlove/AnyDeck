import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';

import '../../../../app/l10n/app_localizations.dart';
import '../../../../core/providers/transfer_provider.dart';

/// 拖拽目标覆盖层组件。
/// 用于在桌面端支持将外部 APK 或文件拖拽至应用窗口以进行安装或上传。
class DragDropTargetOverlay extends ConsumerStatefulWidget {
  const DragDropTargetOverlay({
    super.key,
    required this.child,
    required this.onDragDone,
  });

  /// 被包裹的底层子组件，即被放置于此覆盖层下方的视图内容。
  final Widget child;

  /// 拖拽完成时的回调函数，返回拖拽的文件列表。
  final Function(List<XFile> files) onDragDone;

  @override
  ConsumerState<DragDropTargetOverlay> createState() =>
      _DragDropTargetOverlayState();
}

class _DragDropTargetOverlayState extends ConsumerState<DragDropTargetOverlay> {
  // 标识当前是否有文件正被拖拽在窗口上方
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    // 监听全局传输任务列表（例如 APK 安装或文件上传）
    final transferTasks = ref.watch(transferListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DropTarget(
      // 拖拽文件进入窗口区域
      onDragEntered: (details) {
        setState(() {
          _isDragging = true;
        });
      },
      // 拖拽离开窗口区域
      onDragExited: (details) {
        setState(() {
          _isDragging = false;
        });
      },
      // 拖拽在窗口内松手完成放置
      onDragDone: (details) {
        setState(() {
          _isDragging = false;
        });
        widget.onDragDone(details.files);
      },
      child: Stack(
        children: [
          widget.child,
          // 拖拽遮罩层：提示用户可以松手来安装 APK 或上传文件
          if (_isDragging)
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: _isDragging ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.all(32),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 36,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (isDark ? const Color(0xff1e1e1e) : Colors.white)
                                  .withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 32,
                              offset: const Offset(0, 16),
                            ),
                          ],
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2.5,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                CupertinoIcons.cloud_upload_fill,
                                size: 52,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              context.l10n.t('dropToInstallOrUpload'),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // 悬浮的任务传输面板：悬浮于窗口右上角，展示正在运行的任务及历史状态
          if (transferTasks.isNotEmpty)
            Positioned(
              top: 80,
              right: MediaQuery.of(context).size.width < 400 ? 16 : 24,
              child: _TransferTasksPanel(tasks: transferTasks),
            ),
        ],
      ),
    );
  }
}

/// 浮动的文件传输与 APK 安装任务面板。
/// 在右上角悬浮展示当前所有的传输任务及其状态（进行中、成功、失败）。
class _TransferTasksPanel extends ConsumerWidget {
  const _TransferTasksPanel({required this.tasks});

  /// 当前要展示的所有任务列表。
  final List<TransferTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 统计进行中的活跃任务数
    final activeCount = tasks.where((t) => !t.isDone).length;

    // 根据屏幕宽度自适应计算面板宽度
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = screenWidth < 360 ? screenWidth - 32 : 320.0;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: panelWidth,
        decoration: BoxDecoration(
          color: (isDark ? const Color(0xff252629) : Colors.white).withValues(
            alpha: 0.95,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 面板标题区域
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.arrow_2_circlepath_circle,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.l10n.t('fileTransfers'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                // 如果有活跃中的传输任务，显示活跃任务的角标数量
                if (activeCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$activeCount',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // 传输任务列表
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: tasks.length,
                separatorBuilder: (context, index) => const Divider(height: 16),
                itemBuilder: (context, index) {
                  final task = tasks[index];

                  Widget statusWidget;
                  String statusText;
                  Color statusColor;

                  // 根据任务的当前状态判断应显示的文本、图标以及颜色
                  if (!task.isDone) {
                    // 正在进行中
                    statusWidget = const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                    statusText = task.pendingLabelKey != null
                        ? context.l10n.t(task.pendingLabelKey!)
                        : task.isApk
                        ? context.l10n.t('installingApk')
                        : context.l10n.t('uploadingFile');
                    statusColor = theme.colorScheme.onSurfaceVariant;
                  } else if (task.isSuccess) {
                    // 传输/安装成功
                    statusWidget = const Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: Colors.green,
                      size: 16,
                    );
                    statusText = task.successLabelKey != null
                        ? context.l10n.t(task.successLabelKey!)
                        : task.isApk
                        ? context.l10n.t('installSuccess')
                        : context.l10n.t('uploadSuccess');
                    statusColor = Colors.green;
                  } else {
                    // 发生错误
                    statusWidget = const Icon(
                      CupertinoIcons.xmark_circle_fill,
                      color: Colors.red,
                      size: 16,
                    );
                    statusText = task.error ?? context.l10n.t('error');
                    statusColor = Colors.red;
                  }

                  return Row(
                    children: [
                      // 根据任务类型显示对应的图标（APK使用应用角标图标，普通文件使用文档图标）
                      Icon(
                        task.isApk
                            ? CupertinoIcons.app_badge
                            : CupertinoIcons.doc,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 任务名称（如文件名）
                            Text(
                              task.name,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            // 当前状态描述文本
                            Text(
                              statusText,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: statusColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // 右侧的状态指示图标/进度条
                      statusWidget,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
