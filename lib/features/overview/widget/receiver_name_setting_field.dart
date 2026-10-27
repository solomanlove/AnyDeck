import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/airplay/airplay_server_service.dart';

/// 投屏接收端名称编辑组件，供设置页及接收管理页的 AirPlay 与 DLNA 共用。
///
/// 用途：在“设置 -> 投屏设置”中展示并修改手机投屏设备列表中的接收端名称。
/// 参数说明：
/// - [value]: 当前保存的接收端名称。
/// - [defaultName]: 空白输入和恢复默认时使用的名称。
/// - [onChanged]: 名称提交变更时的持久化回调。
/// - [resetTooltip]: 恢复默认名称按钮的悬停提示文案。
/// - [onApplied]: 提交后需要执行的协议专属操作。
///
/// 用法示例：
/// ```dart
/// ReceiverNameSettingField(
///   value: settings.airplayServerName,
///   defaultName: AppSettings.defaultAirplayServerName,
///   resetTooltip: '恢复默认',
///   onChanged: controller.setAirplayServerName,
/// )
/// ```
class ReceiverNameSettingField extends ConsumerStatefulWidget {
  const ReceiverNameSettingField({
    super.key,
    required this.value,
    required this.defaultName,
    required this.onChanged,
    required this.resetTooltip,
    this.onApplied,
  });

  /// 当前配置的接收端名称
  final String value;

  /// 空白输入时恢复的默认名称
  final String defaultName;

  /// 提交新名称时的回调
  final ValueChanged<String> onChanged;

  /// 恢复默认按钮提示文案
  final String resetTooltip;

  /// 提交后的协议专属处理
  final void Function(WidgetRef ref, String name)? onApplied;

  @override
  ConsumerState<ReceiverNameSettingField> createState() =>
      _ReceiverNameSettingFieldState();
}

class _ReceiverNameSettingFieldState
    extends ConsumerState<ReceiverNameSettingField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant ReceiverNameSettingField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !_focusNode.hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _commit(_controller.text);
    }
  }

  void _commit(String raw) {
    final trimmed = raw.trim();
    final resolved = trimmed.isEmpty ? widget.defaultName : trimmed;
    if (_controller.text != resolved) {
      _controller.text = resolved;
    }
    if (resolved == widget.value) return;
    widget.onChanged(resolved);
    widget.onApplied?.call(ref, resolved);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCustom = widget.value != widget.defaultName;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isCustom) ...[
          Tooltip(
            message: widget.resetTooltip,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _commit(widget.defaultName),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  CupertinoIcons.refresh,
                  size: 14,
                  color: isDark ? Colors.white54 : const Color(0xFF64748B),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        SizedBox(
          width: 200,
          height: 32,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            onSubmitted: _commit,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.defaultName,
              hintStyle: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.white,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: AppPalette.primary,
                  width: 1.2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// AirPlay 空闲广播时以新名称重新发布，不影响正在镜像的 iPhone。
void restartAirplayBroadcastIfIdle(WidgetRef ref, String name) {
  final session = ref.read(airplaySessionProvider);
  if (session != null &&
      !session.hasAnyMirroring &&
      session.hasAnyBroadcasting) {
    unawaited(
      ref.read(airplaySessionProvider.notifier).startServer(name: name),
    );
  }
}
