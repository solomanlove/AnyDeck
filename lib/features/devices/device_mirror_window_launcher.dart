part of '../dashboard_screen.dart';

/// 打开独立投屏窗口的全局辅助方法
Future<void> openStandaloneMirrorWindow(
  BuildContext context,
  WidgetRef ref,
  DiscoveredDevice device,
) async {
  if (!device.isOnline) {
    AppToast.show(context, context.l10n.t('selectDeviceToMirror'), isError: true);
    return;
  }

  // DiscoveredDevice 不包含别名，按设备身份从注册表读取用户配置的名称。
  var deviceName = device.displayName;
  String? physicalDeviceKey;
  for (final registered in ref.read(deviceRegistryProvider)) {
    if (registered.id == device.id ||
        registered.serial == device.id ||
        registered.connections.contains(device.id)) {
      final customName = registered.customName?.trim();
      if (customName != null && customName.isNotEmpty) {
        deviceName = customName;
      }
      physicalDeviceKey = FusionModePreference.knownPhysicalKey(registered, device.id);
      break;
    }
  }
  final windowTitle = context.l10n
      .t('screenMirrorTitle')
      .replaceAll('{name}', deviceName);

  // 1. If mirroring is active, stop it first.
  if (device.isIos) {
    final activeIos = ref.read(activeIosMirrorProvider(device.id));
    if (activeIos != null) {
      await ref.read(activeIosMirrorProvider(device.id).notifier).forceStop();
    }
  } else {
    final textureId = ref.read(activeEmbeddedMirrorProvider(device.id));
    if (textureId != null) {
      await ref
          .read(activeEmbeddedMirrorProvider(device.id).notifier)
          .forceStop();
    }
  }

  // 2. Open the standalone mirroring window
  try {
    // 点击安卓投屏和鸿蒙投屏前，先主动快速获取手机当前实际宽高比
    final aspect = await MirrorAspectResolver.fetchDeviceAspectRatioBeforeMirror(
      ref: ref,
      deviceId: device.id,
      isHarmony: device.isHarmony,
      isIos: device.isIos,
    );
    final overviewAsync = ref.read(deviceOverviewProvider(device.id));
    final resolution = overviewAsync.maybeWhen(
      data: (overview) => overview.physicalResolution,
      orElse: () => null,
    );
    final initialSize =
        resolveMirrorInitialWindowSize(resolution, ratio: aspect);
    await createAdbManageWindow(
      arguments: {
        'type': 'mirror',
        'deviceId': device.id,
        'physicalDeviceKey': physicalDeviceKey,
        'deviceName': deviceName,
        'alwaysOnTop': ref.read(appSettingsProvider).scrcpyAlwaysOnTop,
        'isIos': device.isIos,
        'isHarmony': device.isHarmony,
      },
      frame: Offset.zero & initialSize,
      title: windowTitle,
    );
  } catch (e) {
    debugPrint('Failed to open standalone mirror window: $e');
  }
}
