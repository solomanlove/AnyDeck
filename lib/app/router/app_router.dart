import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_providers.dart';
import '../../features/dashboard_screen.dart';
import 'dashboard_route.dart';

import '../../features/developer/developer_options_screen.dart';

/// 全局 GoRouter 实例，集中管理路由，避免页面路径散落在业务组件中。
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: _initialLocation(ref),
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/devices'),
      GoRoute(
        path: '/developer-options',
        name: AppRouteNames.developerOptions,
        builder: (context, state) => const DeveloperOptionsScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return Stack(
            fit: StackFit.expand,
            children: [
              DashboardScreen(route: DashboardRouteState.fromUri(state.uri)),
              // 保留 ShellRoute 的内层 Navigator 以承载详情返回栈，业务画面仍由 Dashboard 统一渲染。
              Offstage(offstage: true, child: child),
            ],
          );
        },
        routes: [
          GoRoute(
            path: '/devices',
            name: AppRouteNames.devices,
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/emulators',
            name: AppRouteNames.emulators,
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/settings',
            name: AppRouteNames.settings,
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/wan-android',
            name: AppRouteNames.wanAndroid,
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/mcp',
            name: AppRouteNames.mcp,
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/devices/:deviceId/apps/:packageName',
            name: AppRouteNames.appDetails,
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/devices/:deviceId/:tool',
            name: AppRouteNames.deviceTool,
            redirect: (context, state) {
              final tool = state.pathParameters['tool'];
              if (tool != null && tabIndexForToolSlug(tool) != null) {
                return null;
              }
              final deviceId = state.pathParameters['deviceId'];
              return deviceId == null
                  ? '/devices'
                  : '/devices/${Uri.encodeComponent(deviceId)}/overview';
            },
            builder: (context, state) => const SizedBox.shrink(),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// 兼容测试桩和窗口恢复时已注入的选择状态；正常冷启动仍落在设备管理页。
String _initialLocation(Ref ref) {
  final tabIndex = ref.read(selectedToolTabProvider);
  if (tabIndex == -2) return '/emulators';
  if (tabIndex == 12) return '/settings';
  if (tabIndex == 13) return '/wan-android';
  if (tabIndex == 14) return '/mcp';

  final device = ref.read(selectedDeviceProvider);
  if (device != null && tabIndex >= 0) {
    return '/devices/${Uri.encodeComponent(device.id)}/${toolSlugForTabIndex(tabIndex)}';
  }
  return '/devices';
}
