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

    var iconPath = package.iconLocalPath;
    if (iconPath == null || !File(iconPath).existsSync()) {
      iconPath = ref
          .read(packageMetadataResolverProvider)
          .findIconOnDisk(package.name, preferredDeviceId: deviceId);
    }

    if (iconPath == null || !File(iconPath).existsSync()) return fallback;
    return Image.file(
      File(iconPath),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}
