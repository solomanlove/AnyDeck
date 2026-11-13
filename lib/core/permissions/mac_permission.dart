/// AnyDeck 使用的 macOS 权限；系统标识与展示文案分离。
enum MacPermission {
  localNetwork('macPermissionLocalNetwork', 'macPermissionLocalNetworkDesc'),
  bluetooth('macPermissionBluetooth', 'macPermissionBluetoothDesc', true),
  location('macPermissionLocation', 'macPermissionLocationDesc', true),
  camera('macPermissionCamera', 'macPermissionCameraDesc', true),
  notifications(
    'macPermissionNotifications',
    'macPermissionNotificationsDesc',
    true,
  ),
  files('macPermissionFiles', 'macPermissionFilesDesc'),
  cameraExtension(
    'macPermissionCameraExtension',
    'macPermissionCameraExtensionDesc',
  ),
  loginItems('macPermissionLoginItems', 'macPermissionLoginItemsDesc');

  const MacPermission(
    this.titleKey,
    this.descriptionKey, [
    this.supportsRequest = false,
  ]);

  final String titleKey;
  final String descriptionKey;
  final bool supportsRequest;
}

/// manual 表示系统未提供可靠查询接口，不等同于未授权。
enum MacPermissionStatus {
  authorized('macPermissionStatusAuthorized'),
  notDetermined('macPermissionStatusNotDetermined'),
  denied('macPermissionStatusDenied'),
  restricted('macPermissionStatusRestricted'),
  disabled('macPermissionStatusDisabled'),
  manual('macPermissionStatusManual'),
  unsupported('macPermissionStatusUnsupported'),
  notRequired('macPermissionStatusNotRequired'),
  unknown('macPermissionStatusUnknown');

  const MacPermissionStatus(this.labelKey);
  final String labelKey;

  static MacPermissionStatus parse(Object? value) {
    return values.firstWhere(
      (status) => status.name == value,
      orElse: () => unknown,
    );
  }
}

/// 页面短期状态，不缓存系统授权结论到 Preferences。
class MacPermissionsState {
  const MacPermissionsState({
    this.statuses = const {},
    this.loading = true,
    this.busy,
    this.errorKey,
  });

  final Map<MacPermission, MacPermissionStatus> statuses;
  final bool loading;
  final MacPermission? busy;
  final String? errorKey;

  MacPermissionStatus statusFor(MacPermission permission) =>
      statuses[permission] ?? MacPermissionStatus.unknown;
}
