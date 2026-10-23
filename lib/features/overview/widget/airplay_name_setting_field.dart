import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/app_settings.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/airplay/airplay_server_service.dart';

/// 设置页 iOS AirPlay 投屏广播名称编辑组件。
///
/// 用途：在“设置 -> 投屏设置”中展示并修改 iOS 控制中心屏幕镜像列表显示的接收端名称。
/// 参数说明：
/// - [value]: 当前保存的 AirPlay 接收端名称（默认 `AnyDeck-AirPlay`）。
/// - [onChanged]: 名称提交变更时的持久化回调。
/// - [resetTooltip]: 恢复默认名称按钮的悬停提示文案。
///
/// 用法示例：
/// ```dart
/// AirPlayNameSettingField(
///   value: settings.airplayServerName,
///   resetTooltip: '恢复默认',
///   onChanged: controller.setAirplayServerName,
/// )
/// ```
class AirPlayNameSettingField extends ConsumerStatefulWidget {
  const AirPlayNameSettingField({
    super.key,
    required this.value,
    required this.onChanged,
    this.resetTooltip = 'AnyDeck-AirPlay',
  });

  /// 当前配置的 AirPlay 服务名称
  final String value;

  /// 提交新名称时的回调
  final ValueChanged<String> onChanged;

  /// 恢复默认按钮提示文案
  final String resetTooltip;

  @override
  ConsumerState<AirPlayNameSettingField> createState() =>
      _AirPlayNameSettingFieldState();
}

class _AirPlayNameSettingFieldState
    extends ConsumerState<AirPlayNameSettingField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant AirPlayNameSettingField oldWidget) {
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
    final resolved = trimmed.isEmpty
        ? AppSettings.defaultAirplayServerName
        : trimmed;
    if (_controller.text != resolved) {
      _controller.text = resolved;
    }
    if (resolved == widget.value) return;
    widget.onChanged(resolved);

    // 若当前 AirPlay 处于空闲广播态（无设备正在投屏），自动使用新名称重启广播
    final session = ref.read(airplaySessionProvider);
    if (session != null &&
        !session.hasAnyMirroring &&
        session.hasAnyBroadcasting) {
      unawaited(
        ref.read(airplaySessionProvider.notifier).startServer(name: resolved),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCustom = widget.value != AppSettings.defaultAirplayServerName;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isCustom) ...[
          Tooltip(
            message: widget.resetTooltip,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _commit(AppSettings.defaultAirplayServerName),
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
              hintText: AppSettings.defaultAirplayServerName,
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
