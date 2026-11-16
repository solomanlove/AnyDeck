/// 折叠设备的物理屏幕角色，不绑定会随姿态变化的逻辑 display ID。
enum FoldableScreen { inner, outer }

/// 投屏会话的屏幕选择；automatic 交还设备的真实折叠姿态决定。
enum FoldableScreenMode { automatic, inner, outer }

/// 由运行时普通姿态和双向布局映射共同确认的切屏能力。
class FoldableScreenCapability {
  const FoldableScreenCapability({
    required this.innerStateId,
    required this.outerStateId,
    required this.innerPhysicalId,
    required this.outerPhysicalId,
  });

  final int innerStateId;
  final int outerStateId;
  final String innerPhysicalId;
  final String outerPhysicalId;
}

/// 系统已提交的屏幕选择与覆盖状态，供会话控制器同步工具栏。
class FoldableScreenSnapshot {
  const FoldableScreenSnapshot({
    required this.capability,
    required this.currentScreen,
    required this.committedStateId,
    this.overrideStateId,
    required this.hasOverride,
  });

  final FoldableScreenCapability capability;

  /// 当前姿态没有可识别的主屏布局时为 null，避免误报切屏成功。
  final FoldableScreen? currentScreen;
  final int committedStateId;
  final int? overrideStateId;

  /// 包含其他进程创建的覆盖；控制器不得据此认领其所有权。
  final bool hasOverride;
}
