import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widget/local_log_capture_button.dart';
import 'console_toolbar_button.dart';

/// 底部控制台的紧凑操作栏；窄屏横向滚动筛选工具，始终保留弹出与关闭入口。
///
/// 搜索与筛选状态由日志视图持有，回调仅表达操作；不拖动原生窗口。
class ConsoleEmbeddedToolbar extends StatelessWidget {
  const ConsoleEmbeddedToolbar({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.keyLogsOnly,
    required this.onToggleKeyLogs,
    required this.hideHeartbeats,
    required this.onToggleHeartbeats,
    required this.autoScroll,
    required this.onToggleAutoScroll,
    required this.onCopy,
    required this.onClear,
    this.onPopOut,
    this.onClose,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final bool keyLogsOnly;
  final VoidCallback onToggleKeyLogs;
  final bool hideHeartbeats;
  final VoidCallback onToggleHeartbeats;
  final bool autoScroll;
  final VoidCallback onToggleAutoScroll;
  final VoidCallback onCopy;
  final VoidCallback onClear;
  final VoidCallback? onPopOut;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Text(context.l10n.t('console'), style: theme.textTheme.titleSmall),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 8,
                children: [
                  SizedBox(
                    width: 160,
                    height: 36,
                    child: TextField(
                      controller: searchController,
                      onChanged: onSearchChanged,
                      style: theme.textTheme.bodySmall,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: context.l10n.t('searchLogsHint'),
                        prefixIcon: const Icon(CupertinoIcons.search, size: 16),
                        contentPadding: EdgeInsets.zero,
                        border: const OutlineInputBorder(
                          borderRadius: AppThemeSizes.radiusMedium,
                        ),
                      ),
                    ),
                  ),
                  ConsoleToolbarButton(
                    key: const Key('consoleKeyLogsFilter'),
                    tooltip: context.l10n.t('consoleKeyLogs'),
                    icon: Icons.filter_alt_outlined,
                    selected: keyLogsOnly,
                    onPressed: onToggleKeyLogs,
                  ),
                  LocalLogCaptureButton(
                    iconOnly: true,
                    iconButtonStyle: consoleToolbarButtonStyle(theme),
                  ),
                  ConsoleToolbarButton(
                    tooltip: context.l10n.t('hideHeartbeats'),
                    icon: Icons.monitor_heart_outlined,
                    selected: hideHeartbeats,
                    onPressed: onToggleHeartbeats,
                  ),
                  ConsoleToolbarButton(
                    tooltip: context.l10n.t('autoScroll'),
                    icon: Icons.vertical_align_bottom_rounded,
                    selected: autoScroll,
                    onPressed: onToggleAutoScroll,
                  ),
                  ConsoleToolbarButton(
                    tooltip: context.l10n.t('copyAll'),
                    icon: CupertinoIcons.doc_on_doc,
                    onPressed: onCopy,
                  ),
                  ConsoleToolbarButton(
                    tooltip: context.l10n.t('clear'),
                    icon: CupertinoIcons.trash,
                    onPressed: onClear,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            key: const Key('consoleDockPopOut'),
            onPressed: onPopOut,
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(context.l10n.t('consolePopOut')),
          ),
          IconButton(
            key: const Key('consoleDockClose'),
            tooltip: context.l10n.t('close'),
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
