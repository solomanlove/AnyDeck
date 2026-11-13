/// 需要在系统设置手动批准的 macOS 能力；系统标识与展示文案分离。
enum MacPermission {
  cameraExtension(
    'macPermissionCameraExtension',
    'macPermissionCameraExtensionDesc',
  ),
  loginItems('macPermissionLoginItems', 'macPermissionLoginItemsDesc');

  const MacPermission(this.titleKey, this.descriptionKey);

  final String titleKey;
  final String descriptionKey;
}

/// manual 表示需要在系统设置确认或处理，不等同于已拒绝。
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
