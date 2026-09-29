import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../adb/adb_device.dart';
import '../../logcat/logcat_controller.dart';
import '../../logcat/logcat_state.dart';
import '../../scrcpy/scrcpy_session.dart';
import 'service_providers.dart';

/// Logcat 进程控制器和可见日志状态 Provider。
final logcatControllerProvider =
    NotifierProvider<LogcatController, LogcatState>(LogcatController.new);

/// 当前选中的 Dashboard 业务工具 Tab 下标 Provider。
///
/// -1 代表设备管理主页，-2 代表与设备管理同级的模拟器列表。
final selectedToolTabProvider = NotifierProvider<ToolTabNotifier, int>(
  ToolTabNotifier.new,
);

/// 工具 Tab 下标状态控制器。
class ToolTabNotifier extends Notifier<int> {
  @override
  int build() => -1;

  /// 按 TabBar 下标选择 Tab。
  /// 旧索引 8（布局分析）归一到 9（截图录屏）。
  void select(int index) {
    state = (index == 8) ? 9 : index;
  }
}

/// Workspace 面板当前选中的 ADB / 鸿蒙 / iOS 设备 Provider。
final selectedDeviceProvider =
    NotifierProvider<SelectedDeviceNotifier, AdbDevice?>(
      SelectedDeviceNotifier.new,
    );

/// 当前选中设备状态控制器。
///
/// 在切换设备或清空时自动移除原有设备的 Web 调试端口转发，并重置选中应用。
class SelectedDeviceNotifier extends Notifier<AdbDevice?> {
  @override
  AdbDevice? build() => null;

  /// 从左侧设备列表中选择指定设备。
  void select(AdbDevice device) {
    final old = state;
    if (old != null && old.id != device.id) {
      ref.read(webDebugServiceProvider).removeForwards(old.id);
    }
    ref.read(selectedAppPackageProvider.notifier).state = null;
    state = device;
  }

  /// 清空选择，使 Workspace 回退到未选中设备的主页状态。
  void clear() {
    final old = state;
    if (old != null) {
      ref.read(webDebugServiceProvider).removeForwards(old.id);
    }
    ref.read(selectedAppPackageProvider.notifier).state = null;
    state = null;
  }
}

/// 当前选中的应用包名 Provider。
final selectedAppPackageProvider =
    NotifierProvider<SelectedAppPackageNotifier, String?>(
      SelectedAppPackageNotifier.new,
    );

/// 应用包名选择状态控制器。
class SelectedAppPackageNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  @override
  set state(String? value) => super.state = value;
}

/// 用户是否手动清空了选中的设备（例如点击了顶部 Logo 或返回主页）Provider。
final userClearedDeviceSelectionProvider =
    NotifierProvider<UserClearedDeviceSelectionNotifier, bool>(
      UserClearedDeviceSelectionNotifier.new,
    );

/// 用户主动清空设备状态控制器。
class UserClearedDeviceSelectionNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  @override
  set state(bool value) => super.state = value;
}

/// 活跃的 Scrcpy 会话映射表 Provider（以生成的 sessionId 为 key）。
final scrcpySessionsProvider =
    NotifierProvider<ScrcpySessionsNotifier, Map<String, ScrcpySession>>(
      ScrcpySessionsNotifier.new,
    );

/// Scrcpy 会话状态控制器，跟踪各设备的投屏会话供 Dashboard 渲染与生命周期维护。
class ScrcpySessionsNotifier extends Notifier<Map<String, ScrcpySession>> {
  @override
  Map<String, ScrcpySession> build() => {};

  /// 添加新启动的 Scrcpy 会话
  void add(ScrcpySession session) {
    state = {...state, session.id: session};
  }

  /// 后台投屏进程停止后批量移除对应会话
  void removeAll(Iterable<String> sessionIds) {
    final next = Map<String, ScrcpySession>.of(state);
    for (final id in sessionIds) {
      next.remove(id);
    }
    state = next;
  }
}
