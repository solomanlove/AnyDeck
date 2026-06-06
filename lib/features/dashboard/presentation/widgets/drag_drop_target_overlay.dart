import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';

import '../../../../app/l10n/app_localizations.dart';
import '../../../../core/providers/transfer_provider.dart';

class DragDropTargetOverlay extends ConsumerStatefulWidget {
  const DragDropTargetOverlay({
    super.key,
    required this.child,
    required this.onDragDone,
  });

  final Widget child;
  final Function(List<XFile> files) onDragDone;

  @override
  ConsumerState<DragDropTargetOverlay> createState() => _DragDropTargetOverlayState();
}

class _DragDropTargetOverlayState extends ConsumerState<DragDropTargetOverlay> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final transferTasks = ref.watch(transferListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DropTarget(
      onDragEntered: (details) {
        setState(() {
          _isDragging = true;
        });
      },
      onDragExited: (details) {
        setState(() {
          _isDragging = false;
        });
      },
      onDragDone: (details) {
        setState(() {
          _isDragging = false;
        });
        widget.onDragDone(details.files);
      },
      child: Stack(
        children: [
          widget.child,
          // Drag Shadow / Overlay indicating user can drop
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
                          color: (isDark ? const Color(0xff1e1e1e) : Colors.white)
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.1),
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
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
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
          // Floating active transfers list
          if (transferTasks.isNotEmpty)
            Positioned(
              bottom: 24,
              right: MediaQuery.of(context).size.width < 400 ? 16 : 24,
              child: _TransferTasksPanel(tasks: transferTasks),
            ),
        ],
      ),
    );
  }
}

class _TransferTasksPanel extends ConsumerWidget {
  const _TransferTasksPanel({required this.tasks});

  final List<TransferTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final activeCount = tasks.where((t) => !t.isDone).length;

    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = screenWidth < 360 ? screenWidth - 32 : 320.0;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: panelWidth,
        decoration: BoxDecoration(
          color: (isDark ? const Color(0xff252629) : Colors.white)
              .withValues(alpha: 0.95),
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
                if (activeCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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

                  if (!task.isDone) {
                    statusWidget = const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    );
                    statusText = task.isApk
                        ? context.l10n.t('installingApk')
                        : context.l10n.t('uploadingFile');
                    statusColor = theme.colorScheme.onSurfaceVariant;
                  } else if (task.isSuccess) {
                    statusWidget = const Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: Colors.green,
                      size: 16,
                    );
                    statusText = task.isApk
                        ? context.l10n.t('installSuccess')
                        : context.l10n.t('uploadSuccess');
                    statusColor = Colors.green;
                  } else {
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
                      Icon(
                        task.isApk ? CupertinoIcons.app_badge : CupertinoIcons.doc,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.name,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
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
