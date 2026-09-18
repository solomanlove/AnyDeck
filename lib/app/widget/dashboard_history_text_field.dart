import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// 固定显示在历史记录上方的快捷筛选项。
class DashboardHistoryOption {
  const DashboardHistoryOption({required this.value, required this.label});

  final String value;
  final String label;
}

/// 在仪表盘筛选框中展示可选、可删除的搜索历史。
///
/// [controller] 管理输入文本；[history] 为已提交的记录；[defaultOptions] 为不进入历史的固定项。
/// 输入变化调用 [onChanged]，回车或失焦调用 [onSubmitted]，选择记录调用 [onSelected]。
/// [onHistoryRemoved] 删除单条记录；[onHistoryCleared] 与 [onClear] 分别清空历史和输入。
class DashboardHistoryTextField extends StatefulWidget {
  const DashboardHistoryTextField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.history,
    required this.onChanged,
    required this.onSubmitted,
    required this.onSelected,
    required this.onHistoryRemoved,
    this.focusNode,
    this.defaultOptions = const [],
    this.onHistoryCleared,
    this.onClear,
    this.hasQuery = false,
    this.textStyle,
  });

  final TextEditingController controller;
  final String hintText;
  final List<String> history;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onHistoryRemoved;
  final FocusNode? focusNode;
  final List<DashboardHistoryOption> defaultOptions;
  final VoidCallback? onHistoryCleared;
  final VoidCallback? onClear;
  final bool hasQuery;
  final TextStyle? textStyle;

  @override
  State<DashboardHistoryTextField> createState() =>
      _DashboardHistoryTextFieldState();
}

class _DashboardHistoryTextFieldState extends State<DashboardHistoryTextField> {
  final OverlayPortalController _overlayController = OverlayPortalController();
  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;
  bool get _hasOptions =>
      widget.history.isNotEmpty || widget.defaultOptions.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(DashboardHistoryTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasOptions && _overlayController.isShowing) {
      // OverlayPortal 会随输入框刷新内容；只需在选项清空后收起下拉层。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_hasOptions) {
          _hideOverlay();
        }
      });
    }
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      _openHistory();
    } else {
      // 失去焦点时的隐藏由 TapRegion 的 onTapOutside 处理，避免点击下拉列表项时过早卸载 Overlay
    }
  }

  void _selectHistory(String value) {
    widget.controller.text = value;
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    widget.onChanged(value);
    widget.onSelected(value);
    _hideOverlay();
    _focusNode.unfocus();
  }

  void _openHistory() {
    if (_hasOptions) {
      _showOverlay();
    }
  }

  void _toggleHistory() {
    if (_overlayController.isShowing) {
      _hideOverlay();
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
      _openHistory();
    }
  }

  void _showOverlay() {
    if (!mounted || !_hasOptions) return;
    _overlayController.show();
  }

  void _hideOverlay() {
    if (_overlayController.isShowing) _overlayController.hide();
  }

  Widget _buildDropdownOverlayContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      color: isDark ? const Color(0xff1e293b) : Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
            width: 1,
          ),
        ),
        constraints: const BoxConstraints(maxHeight: 250),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final option in widget.defaultOptions)
              InkWell(
                canRequestFocus: false,
                onTap: () => _selectHistory(option.value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Text(
                    option.label,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            if (widget.history.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.t('searchHistory'),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.7),
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    if (widget.onHistoryCleared != null)
                      TextButton(
                        onPressed: widget.onHistoryCleared,
                        child: Text(context.l10n.t('clear')),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: widget.history.length,
                  itemBuilder: (context, index) {
                    final item = widget.history[index];
                    return InkWell(
                      canRequestFocus: false,
                      onTap: () {
                        _selectHistory(item);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              CupertinoIcons.clock,
                              size: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item,
                                style: Theme.of(context).textTheme.bodyMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                widget.onHistoryRemoved(item);
                                if (widget.controller.text == item) {
                                  widget.controller.clear();
                                  widget.onChanged('');
                                }
                              },
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: Icon(
                                  CupertinoIcons.clear,
                                  size: 14,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _overlayController,
      overlayChildBuilder: (context, info) {
        final origin = MatrixUtils.transformPoint(
          info.childPaintTransform,
          Offset.zero,
        );
        return Positioned(
          left: origin.dx,
          top: origin.dy + info.childSize.height + 4,
          width: info.childSize.width,
          child: TapRegion(
            groupId: 'dashboard_history_filter_region_${identityHashCode(this)}',
            child: _buildDropdownOverlayContent(),
          ),
        );
      },
      child: SizedBox(
        height: 38,
        child: TapRegion(
          groupId: 'dashboard_history_filter_region_${identityHashCode(this)}',
          onTapOutside: (_) {
            widget.onSubmitted(widget.controller.text);
            _hideOverlay();
            _focusNode.unfocus();
          },
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            minLines: 1,
            maxLines: 1,
            style: widget.textStyle ?? const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              suffixIcon:
                  !_hasOptions && !(widget.hasQuery && widget.onClear != null)
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.hasQuery && widget.onClear != null)
                          IconButton(
                            icon: const Icon(CupertinoIcons.clear, size: 16),
                            onPressed: widget.onClear,
                          ),
                        if (_hasOptions)
                          IconButton(
                            tooltip: context.l10n.t('logcatFilterHistory'),
                            icon: const Icon(
                              CupertinoIcons.chevron_down,
                              size: 16,
                            ),
                            onPressed: _toggleHistory,
                          ),
                      ],
                    ),
              suffixIconConstraints: const BoxConstraints(minWidth: 30),
              hintText: widget.hintText,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
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
            textInputAction: TextInputAction.done,
            onTap: _openHistory,
            onChanged: widget.onChanged,
            onSubmitted: (value) {
              widget.onSubmitted(value);
              _hideOverlay();
              _focusNode.unfocus();
            },
          ),
        ),
      ),
    );
  }
}
