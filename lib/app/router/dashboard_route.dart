import 'package:flutter/foundation.dart';

/// 主窗口中的稳定路由名称，业务组件只能通过名称跳转，避免散落路径字符串。
abstract final class AppRouteNames {
  static const devices = 'devices';
  static const emulators = 'emulators';
  static const settings = 'settings';
  static const wanAndroid = 'wanAndroid';
  static const mcp = 'mcp';
  static const deviceTool = 'deviceTool';
  static const appDetails = 'appDetails';
}

/// 主窗口路由对应的页面类型。
enum DashboardRouteKind {
  devices,
  emulators,
  settings,
  wanAndroid,
  mcp,
  deviceTool,
}

/// 从 URI 解析出的主窗口导航状态。
@immutable
class DashboardRouteState {
  const DashboardRouteState._({
    required this.kind,
    required this.tabIndex,
    this.deviceId,
    this.packageName,
  });

  const DashboardRouteState.devices()
    : this._(kind: DashboardRouteKind.devices, tabIndex: -1);

  const DashboardRouteState.emulators()
    : this._(kind: DashboardRouteKind.emulators, tabIndex: -2);

  const DashboardRouteState.settings()
    : this._(kind: DashboardRouteKind.settings, tabIndex: 12);

  const DashboardRouteState.wanAndroid()
    : this._(kind: DashboardRouteKind.wanAndroid, tabIndex: 13);

  const DashboardRouteState.mcp()
    : this._(kind: DashboardRouteKind.mcp, tabIndex: 14);

  const DashboardRouteState.deviceTool({
    required String deviceId,
    required int tabIndex,
    String? packageName,
  }) : this._(
         kind: DashboardRouteKind.deviceTool,
         tabIndex: tabIndex,
         deviceId: deviceId,
         packageName: packageName,
       );

  final DashboardRouteKind kind;
  final int tabIndex;
  final String? deviceId;
  final String? packageName;

  bool get isGlobal => kind != DashboardRouteKind.deviceTool;

  /// ShellRoute 只保留一份 Dashboard，根据完整 URI 恢复业务选中态。
  factory DashboardRouteState.fromUri(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.isEmpty ||
        segments.first == 'devices' && segments.length == 1) {
      return const DashboardRouteState.devices();
    }
    if (segments.first == 'emulators') {
      return const DashboardRouteState.emulators();
    }
    if (segments.first == 'settings') {
      return const DashboardRouteState.settings();
    }
    if (segments.first == 'wan-android') {
      return const DashboardRouteState.wanAndroid();
    }
    if (segments.first == 'mcp') {
      return const DashboardRouteState.mcp();
    }
    if (segments.first == 'devices' && segments.length >= 3) {
      final deviceId = segments[1];
      final tool = segments[2];
      return DashboardRouteState.deviceTool(
        deviceId: deviceId,
        tabIndex: tabIndexForToolSlug(tool) ?? 0,
        packageName: tool == 'apps' && segments.length >= 4
            ? segments[3]
            : null,
      );
    }
    return const DashboardRouteState.devices();
  }

  @override
  bool operator ==(Object other) {
    return other is DashboardRouteState &&
        other.kind == kind &&
        other.tabIndex == tabIndex &&
        other.deviceId == deviceId &&
        other.packageName == packageName;
  }

  @override
  int get hashCode => Object.hash(kind, tabIndex, deviceId, packageName);
}

const Map<int, String> _toolSlugs = {
  0: 'overview',
  1: 'control',
  2: 'apps',
  3: 'files',
  4: 'logs',
  5: 'terminal',
  6: 'processes',
  7: 'webpages',
  9: 'capture',
  10: 'performance',
  11: 'network',
  15: 'messages',
};

String toolSlugForTabIndex(int tabIndex) {
  final normalized = tabIndex == 8 ? 9 : tabIndex;
  return _toolSlugs[normalized] ?? 'overview';
}

int? tabIndexForToolSlug(String slug) {
  for (final entry in _toolSlugs.entries) {
    if (entry.value == slug) return entry.key;
  }
  return null;
}
