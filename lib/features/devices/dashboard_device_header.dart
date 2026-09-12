part of '../dashboard_screen.dart';

const Size _defaultMirrorWindowSize = Size(480, 800);
const double _mirrorWindowTopChromeHeight = 58;

Size _resolveMirrorInitialWindowSize(String? resolution) {
  final ratio = _parseMirrorAspectRatio(resolution);
  if (ratio == null) return _defaultMirrorWindowSize;

  final viewerMaxWidth = _defaultMirrorWindowSize.width;
  final viewerMaxHeight =
      _defaultMirrorWindowSize.height - _mirrorWindowTopChromeHeight;
  final containerRatio = viewerMaxWidth / viewerMaxHeight;

  final double viewerWidth;
  final double viewerHeight;
  if (containerRatio > ratio) {
    viewerHeight = viewerMaxHeight;
    viewerWidth = viewerHeight * ratio;
  } else {
    viewerWidth = viewerMaxWidth;
    viewerHeight = viewerWidth / ratio;
  }

  return Size(
    max(200, viewerWidth),
    max(200, viewerHeight + _mirrorWindowTopChromeHeight),
  );
}

double? _parseMirrorAspectRatio(String? resolution) {
  if (resolution == null || resolution == '-') return null;
  final match = RegExp(r'(\d+)\s*[xX]\s*(\d+)').firstMatch(resolution);
  if (match == null) return null;

  final width = int.tryParse(match.group(1)!);
  final height = int.tryParse(match.group(2)!);
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }
  return width / height;
}

/// 打开独立投屏窗口的全局辅助方法
Future<void> openStandaloneMirrorWindow(
  BuildContext context,
  WidgetRef ref,
  AdbDevice device,
) async {
  if (!device.isOnline) {
    AppToast.show(context, context.l10n.t('selectDeviceToMirror'), isError: true);
    return;
  }

  // AdbDevice 不包含别名，按设备身份从注册表读取用户配置的名称。
  var deviceName = device.displayName;
  for (final registered in ref.read(deviceRegistryProvider)) {
    if (registered.id == device.id ||
        registered.serial == device.id ||
        registered.connections.contains(device.id)) {
      final customName = registered.customName?.trim();
      if (customName != null && customName.isNotEmpty) {
        deviceName = customName;
      }
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
    final overviewAsync = ref.read(deviceOverviewProvider(device.id));
    final resolution = overviewAsync.maybeWhen(
      data: (overview) => overview.physicalResolution,
      orElse: () => null,
    );
    final initialSize = _resolveMirrorInitialWindowSize(resolution);
    await createAdbManageWindow(
      arguments: {
        'type': 'mirror',
        'deviceId': device.id,
        'deviceName': deviceName,
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
