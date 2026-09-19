part of '../dashboard_screen.dart';

class _LogcatToolbar extends StatelessWidget {
  const _LogcatToolbar({
    required this.state,
    required this.packageController,
    required this.tagController,
    required this.textController,
    required this.textFocusNode,
    required this.onViewModeChanged,
    required this.onLevelChanged,
    required this.onPackageChanged,
    required this.onPackageSubmitted,
    required this.onPackageHistoryRemoved,
    required this.onTagChanged,
    required this.onTagSubmitted,
    required this.onTagHistoryRemoved,
    required this.onTextChanged,
    required this.onTextSubmitted,
    required this.onTextHistoryRemoved,
  });

  final LogcatState state;
  final TextEditingController packageController;
  final TextEditingController tagController;
  final TextEditingController textController;
  final FocusNode textFocusNode;
  final ValueChanged<LogcatViewMode> onViewModeChanged;
  final ValueChanged<LogcatLevelFilter> onLevelChanged;
  final ValueChanged<String> onPackageChanged;
  final ValueChanged<String> onPackageSubmitted;
  final ValueChanged<String> onPackageHistoryRemoved;
  final ValueChanged<String> onTagChanged;
  final ValueChanged<String> onTagSubmitted;
  final ValueChanged<String> onTagHistoryRemoved;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<String> onTextSubmitted;
  final ValueChanged<String> onTextHistoryRemoved;

  @override
  Widget build(BuildContext context) {
    final viewModeDropdown = _CompactDropdown<LogcatViewMode>(
      value: state.viewMode,
      items: {
        LogcatViewMode.standard: context.l10n.t('logcatStandardView'),
        LogcatViewMode.compact: context.l10n.t('logcatCompactView'),
        LogcatViewMode.plain: context.l10n.t('logcatPlainView'),
        LogcatViewMode.raw: context.l10n.t('logcatRawView'),
      },
      onChanged: onViewModeChanged,
    );
    final levelDropdown = _CompactDropdown<LogcatLevelFilter>(
      value: state.levelFilter,
      items: {for (final level in LogcatLevelFilter.values) level: level.label},
      onChanged: onLevelChanged,
    );
    final packageField = DashboardHistoryTextField(
      controller: packageController,
      hintText: context.l10n.t('logcatPackageHint'),
      history: state.packageFilterHistory,
      onChanged: onPackageChanged,
      onSubmitted: onPackageSubmitted,
      // 从历史记录选中时直接提交，确保过滤立即生效并写入历史
      onSelected: onPackageSubmitted,
      onHistoryRemoved: onPackageHistoryRemoved,
    );
    final tagField = DashboardHistoryTextField(
      controller: tagController,
      hintText: context.l10n.t('logcatTagHint'),
      history: state.tagFilterHistory,
      onChanged: onTagChanged,
      onSubmitted: onTagSubmitted,
      // 从历史记录选中时直接提交，确保过滤立即生效并写入历史
      onSelected: onTagSubmitted,
      onHistoryRemoved: onTagHistoryRemoved,
    );
    final textField = DashboardHistoryTextField(
      controller: textController,
      focusNode: textFocusNode,
      hintText: context.l10n.t('filterLog'),
      history: state.textFilterHistory,
      onChanged: onTextChanged,
      onSubmitted: onTextSubmitted,
      onSelected: onTextSubmitted,
      onHistoryRemoved: onTextHistoryRemoved,
    );

    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 860) {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: 132, child: viewModeDropdown),
                SizedBox(width: 140, child: levelDropdown),
                SizedBox(width: 220, child: packageField),
                SizedBox(width: 180, child: tagField),
                SizedBox(width: 260, child: textField),
              ],
            );
          }

          return Row(
            children: [
              SizedBox(width: 132, child: viewModeDropdown),
              const SizedBox(width: 8),
              SizedBox(width: 140, child: levelDropdown),
              const SizedBox(width: 8),
              Expanded(flex: 22, child: packageField),
              const SizedBox(width: 8),
              Expanded(flex: 18, child: tagField),
              const SizedBox(width: 8),
              Expanded(flex: 30, child: textField),
            ],
          );
        },
      ),
    );
  }
}

/// 日志左侧垂直操作栏组件
///
/// 包含清空、暂停/恢复、自动滚动、自动换行、导入与导出等常用操作按钮。
class _LogcatLeftToolbar extends StatelessWidget {
  const _LogcatLeftToolbar({
    required this.state,
    required this.onClear,
    required this.onPause,
    required this.onAutoScroll,
    required this.onWrap,
    required this.onImport,
    required this.onExport,
  });

  final LogcatState state;
  final VoidCallback onClear;
  final VoidCallback onPause;
  final VoidCallback onAutoScroll;
  final VoidCallback onWrap;
  final VoidCallback onImport;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 42,
      child: Material(
        color: colorScheme.surfaceContainerLowest,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LogcatIconButton(
                tooltip: context.l10n.t('clear'),
                icon: CupertinoIcons.trash,
                onPressed: onClear,
              ),
              const SizedBox(height: 4),
              _LogcatIconButton(
                tooltip: state.isPaused
                    ? context.l10n.t('logcatResume')
                    : context.l10n.t('logcatPause'),
                icon: state.isPaused
                    ? CupertinoIcons.play
                    : CupertinoIcons.pause,
                iconColor: state.isPaused ? const Color(0xFF4CAF50) : null,
                selected: state.isPaused,
                onPressed: onPause,
              ),
              const SizedBox(height: 4),
              _LogcatIconButton(
                tooltip: context.l10n.t('logcatAutoScroll'),
                icon: CupertinoIcons.arrow_down_to_line,
                selected: state.autoScroll,
                onPressed: onAutoScroll,
              ),
              const SizedBox(height: 4),
              _LogcatIconButton(
                tooltip: context.l10n.t('logcatWrapLines'),
                icon: CupertinoIcons.text_alignleft,
                selected: state.wrapLines,
                onPressed: onWrap,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 6,
                ),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Theme.of(context)
                      .dividerColor
                      .withValues(alpha: 0.4),
                ),
              ),
              _LogcatIconButton(
                tooltip: context.l10n.t('logcatImport'),
                icon: CupertinoIcons.folder_open,
                onPressed: onImport,
              ),
              const SizedBox(height: 4),
              _LogcatIconButton(
                tooltip: context.l10n.t('logcatExport'),
                icon: CupertinoIcons.floppy_disk,
                onPressed: onExport,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactDropdown<T> extends StatelessWidget {
  const _CompactDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isDense: true,
        isExpanded: true,
        borderRadius: BorderRadius.circular(12),
        icon: const Icon(CupertinoIcons.chevron_down, size: 16),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
        ),
        items: items.entries
            .map(
              (entry) => DropdownMenuItem<T>(
                value: entry.key,
                child: Text(
                  entry.value,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(growable: false),
        onChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
      ),
    );
  }
}

class _LogcatIconButton extends StatelessWidget {
  const _LogcatIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    this.iconColor,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        isSelected: selected,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: const EdgeInsets.all(6),
        icon: Icon(
          icon,
          size: 18,
          color: iconColor,
        ),
        onPressed: onPressed,
      ),
    );
  }
}
