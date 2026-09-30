part of '../dashboard_screen.dart';

/// 将 URI 恢复为现有 Dashboard Provider 状态，迁移期保持业务组件无需重复持有导航逻辑。
extension _DashboardRouteSync on _DashboardScreenState {
  void _scheduleDashboardRouteSync() {
    if (widget.route == null || _routeSyncScheduled) return;
    _routeSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeSyncScheduled = false;
      if (!mounted) return;
      _applyDashboardRoute(widget.route!);
    });
  }

  void _applyDashboardRoute(DashboardRouteState route) {
    if (route.isGlobal) {
      _resolvedRouteDeviceId = null;
      if (route.kind == DashboardRouteKind.devices ||
          route.kind == DashboardRouteKind.emulators) {
        ref.read(userClearedDeviceSelectionProvider.notifier).state = true;
        if (ref.read(selectedDeviceProvider) != null) {
          ref.read(selectedDeviceProvider.notifier).clear();
        }
      }
      if (ref.read(selectedToolTabProvider) != route.tabIndex) {
        ref.read(selectedToolTabProvider.notifier).select(route.tabIndex);
      }
      return;
    }

    final deviceId = route.deviceId;
    if (deviceId == null) return;
    final registry = ref.read(deviceRegistryProvider);
    RegisteredDevice? matched;
    for (final device in registry) {
      if (device.id == deviceId ||
          device.serial == deviceId ||
          device.connections.contains(deviceId)) {
        matched = device;
        break;
      }
    }
    if (matched == null) {
      if (_resolvedRouteDeviceId == deviceId) {
        _resolvedRouteDeviceId = null;
        context.goNamed(AppRouteNames.devices);
      }
      return;
    }
    _resolvedRouteDeviceId = deviceId;

    ref.read(userClearedDeviceSelectionProvider.notifier).state = false;
    final selected = ref.read(selectedDeviceProvider);
    if (selected == null || selected.id != matched.toAdbDevice.id) {
      ref.read(selectedDeviceProvider.notifier).select(matched.toAdbDevice);
    }
    if (ref.read(selectedToolTabProvider) != route.tabIndex) {
      ref.read(selectedToolTabProvider.notifier).select(route.tabIndex);
    }
    if (ref.read(selectedAppPackageProvider) != route.packageName) {
      ref.read(selectedAppPackageProvider.notifier).state = route.packageName;
    }
  }

  void _goToDeviceTool(String deviceId, int tabIndex) {
    context.goNamed(
      AppRouteNames.deviceTool,
      pathParameters: {
        'deviceId': deviceId,
        'tool': toolSlugForTabIndex(tabIndex),
      },
    );
  }
}
