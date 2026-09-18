part of '../../dashboard_screen.dart';

/// 应用图标：优先显示设备提取结果，缺失或损坏时按设备系统展示默认图标。
class _PackageIcon extends ConsumerWidget {
  const _PackageIcon({required this.deviceId, required this.package});

  final String deviceId;
  final AdbPackage package;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHarmony = ref.watch(
      deviceRegistryProvider.select(
        (devices) =>
            devices.any((device) => device.id == deviceId && device.isHarmony),
      ),
    );
    final fallback = Image.asset(
      isHarmony
          ? 'assets/brand/harmony_default_app_icon.png'
          : 'assets/brand/android_default_app_icon.png',
      fit: BoxFit.contain,
    );
    final iconPath = package.iconLocalPath;
    if (iconPath == null || !File(iconPath).existsSync()) return fallback;
    return Image.file(
      File(iconPath),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}
