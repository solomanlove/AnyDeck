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
      isHarmony ? AppIcons.harmonyDefaultAppIcon : AppIcons.androidDefaultAppIcon,
      fit: BoxFit.contain,
    );

    // AnyDeck 伴侣应用优先展示自带 App Logo
    if (package.name == 'com.adbmanage.companion') {
      return Image.asset(
        AppIcons.appLogo,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }

    ref.watch(packageMetadataRevisionProvider);
    final resolver = ref.read(packageMetadataResolverProvider);
    final iconPath = resolver.resolve(package, preferredDeviceId: deviceId).iconLocalPath;

    if (iconPath == null) return fallback;
    return Image.file(
      File(iconPath),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        resolver.reportMissingIcon(package.name, iconPath, preferredDeviceId: deviceId);
        return fallback;
      },
    );
  }
}
