import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_theme_sizes.dart';

/// 鸿蒙互联的局部拖放反馈：child 为卡片/中央区域，onDrop 返回整组选中文件。
/// enabled 控制是否接受拖放，circular 用于中央圆形；不依赖 ADB 上传或安装队列。
class HarmonyShareDropTarget extends StatefulWidget {
  const HarmonyShareDropTarget({
    super.key,
    required this.child,
    required this.onDrop,
    required this.enabled,
    this.circular = false,
  });
  final Widget child;
  final ValueChanged<List<File>> onDrop;
  final bool enabled;
  final bool circular;
  @override
  State<HarmonyShareDropTarget> createState() => _HarmonyShareDropTargetState();
}

/// 只在拖入/拖出时重绘当前区域；ValueNotifier 随 Widget 释放，不启动常驻动画。
class _HarmonyShareDropTargetState extends State<HarmonyShareDropTarget> {
  final _hover = ValueNotifier(false);
  @override
  void didUpdateWidget(covariant HarmonyShareDropTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _hover.value = false;
  }

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DropTarget(
    enable: widget.enabled,
    onDragEntered: (_) {
      if (widget.enabled) _hover.value = true;
    },
    onDragExited: (_) => _hover.value = false,
    onDragDone: (details) {
      _hover.value = false;
      if (widget.enabled) {
        widget.onDrop(details.files.map((file) => File(file.path)).toList());
      }
    },
    child: ValueListenableBuilder<bool>(
      valueListenable: _hover,
      child: widget.child,
      builder: (context, hover, child) => Container(
        foregroundDecoration: BoxDecoration(
          shape: widget.circular ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: widget.circular ? null : AppThemeSizes.radiusLarge,
          border: Border.all(
            width: AppThemeSizes.strongBorderWidth,
            color: hover
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
          ),
        ),
        child: child,
      ),
    ),
  );
}
