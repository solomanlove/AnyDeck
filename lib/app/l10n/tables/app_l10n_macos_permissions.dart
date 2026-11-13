/// macOS 权限管理文案；状态未知与系统中查看不能替代真实授权结果。
const macosPermissionsZh = {
  'macPermissionsTitle': 'macOS 权限',
  'macPermissionsDescription':
      '按功能需要授权，返回 AnyDeck 后自动刷新授权状态。',
  'macPermissionsRefresh': '刷新状态',
  'macPermissionsRequest': '申请授权',
  'macPermissionsOpenSettings': '打开系统设置',
  'macPermissionsLoading': '正在读取…',
  'macPermissionReadFailed': '权限状态读取失败，请刷新重试。',
  'macPermissionRequestFailed': '授权申请未完成，请重试或在系统设置中查看。',
  'macPermissionOpenFailed': '无法打开系统设置，请从 Apple 菜单手动进入。',
  'macPermissionBluetooth': '蓝牙',
  'macPermissionBluetoothDesc': '用于附近分享设备的发现与连接。',
  'macPermissionLocation': '定位服务',
  'macPermissionLocationDesc': '用于读取当前 Wi-Fi 名称，以及按指定 Wi-Fi 自动共享设备，不获取地理坐标。',
  'macPermissionCamera': '相机',
  'macPermissionCameraDesc':
      '用于 iPhone USB 投屏。macOS 将这条屏幕采集链路归入相机权限，不会启用 Mac 摄像头。',
  'macPermissionNotifications': '通知',
  'macPermissionNotificationsDesc': '用于设备连接提醒、手机消息转发和文件接收提醒。',
  'macPermissionCameraExtension': '摄像头扩展',
  'macPermissionCameraExtensionDesc':
      '用于将 Android 手机摄像头提供给 Mac 视频应用。当前版本不可用时，请继续使用手机摄像头预览。',
  'macPermissionLoginItems': '登录项',
  'macPermissionLoginItemsDesc': '用于登录 macOS 时自动启动 AnyDeck，可在常规设置中开启自启动。',
  'macPermissionStatusAuthorized': '已授权',
  'macPermissionStatusNotDetermined': '尚未授权',
  'macPermissionStatusDenied': '未授权',
  'macPermissionStatusRestricted': '系统限制',
  'macPermissionStatusDisabled': '已关闭',
  'macPermissionStatusManual': '请在系统设置查看',
  'macPermissionStatusUnsupported': '当前版本不可用',
  'macPermissionStatusNotRequired': '此系统无需单独授权',
  'macPermissionStatusUnknown': '状态未知',
};

const macosPermissionsEn = {
  'macPermissionsTitle': 'macOS Permissions',
  'macPermissionsDescription':
      'Grant access as needed. Permission statuses refresh when you return to AnyDeck.',
  'macPermissionsRefresh': 'Refresh status',
  'macPermissionsRequest': 'Request access',
  'macPermissionsOpenSettings': 'Open System Settings',
  'macPermissionsLoading': 'Reading…',
  'macPermissionReadFailed':
      'Could not read permission statuses. Refresh to retry.',
  'macPermissionRequestFailed':
      'The access request could not be completed. Retry or check System Settings.',
  'macPermissionOpenFailed':
      'Could not open System Settings. Open it manually from the Apple menu.',
  'macPermissionBluetooth': 'Bluetooth',
  'macPermissionBluetoothDesc':
      'Discover and connect to nearby sharing devices.',
  'macPermissionLocation': 'Location Services',
  'macPermissionLocationDesc':
      'Read the current Wi-Fi name and share devices automatically on selected Wi-Fi networks. No geographic coordinates are requested.',
  'macPermissionCamera': 'Camera',
  'macPermissionCameraDesc':
      'Mirror an iPhone over USB. macOS treats this screen capture connection as camera access; the Mac camera stays off.',
  'macPermissionNotifications': 'Notifications',
  'macPermissionNotificationsDesc':
      'Show device connection alerts, forwarded phone notifications, and incoming file alerts.',
  'macPermissionCameraExtension': 'Camera Extension',
  'macPermissionCameraExtensionDesc':
      'Make an Android phone camera available to Mac video apps. If unavailable in this version, use the phone camera preview.',
  'macPermissionLoginItems': 'Login Items',
  'macPermissionLoginItemsDesc':
      'Start AnyDeck when you log in to macOS. Enable launch at startup in General settings.',
  'macPermissionStatusAuthorized': 'Authorized',
  'macPermissionStatusNotDetermined': 'Not yet requested',
  'macPermissionStatusDenied': 'Not authorized',
  'macPermissionStatusRestricted': 'Restricted by system',
  'macPermissionStatusDisabled': 'Disabled',
  'macPermissionStatusManual': 'Check in System Settings',
  'macPermissionStatusUnsupported': 'Unavailable in this version',
  'macPermissionStatusNotRequired': 'No separate permission required',
  'macPermissionStatusUnknown': 'Unknown status',
};
