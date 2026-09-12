/// 使用时长最小闭环文案；统计口径与授权说明中英文保持一致。
const usageZh = {
  'usageTitle': '使用时长',
  'usageIntro': '手机端按需读取系统日统计，通过 ADB 同步。名称和图标复用应用列表缓存。',
  'usageInstall': '安装手机端',
  'usageOpen': '打开手机端',
  'usageSync': '同步使用时长',
  'usageClear': '清除电脑快照',
  'usageSetupHint': '在手机端开启 ADB 共享，并在系统设置授予使用情况访问权限，然后点击同步。',
  'usageEmpty': '尚无快照。先安装手机端并完成授权，再同步。',
  'usageBucketNote':
      '查询手机今日记录；Android 可能扩展到系统日桶，区间见下方。屏幕交互包含亮屏可交互状态；App 前台时间可能重叠。数据可能延迟，不等同于精确自然日或系统健康使用手机报告。',
  'usageScreen': '屏幕交互时长',
  'usageCombined': 'App 前台累计（可重叠）',
  'usageUnavailable': '系统未提供',
  'usageRange': '统计区间',
  'usageSnapshotTime': '快照生成时间',
  'usageDeviceTime': '手机时区',
  'usageAndroidUser': 'Android 用户',
  'usageCachedNote': '显示最后保存的快照，非实时数据；同步失败时保留此快照。',
  'usageNoApps': '系统返回了统计，但没有正时长的 App 记录。',
  'usageSyncDone': '已同步并保存到电脑。',
  'usageCacheCleared': '电脑快照已清除。',
  'usageSharingDisabled': '手机端尚未开启 ADB 共享，或共享已暂停。',
  'usagePermissionRequired': '手机端缺少使用情况访问权限，请在手机系统设置授权。',
  'usageUserLocked': '请在手机重启后先解锁一次再同步。',
  'usageNoData': '系统未返回统计数据，不代表使用时长为零。',
  'usageReadFailed': '读取失败，请检查手机端状态后重试。',
  'usageInvalidResponse': '手机端响应无效或版本不兼容，请检查或更新手机端。',
  'usageConnectionFailed': 'ADB 通信失败，请检查设备连接后重试。',
  'usageCompanionMissing': '当前 Android 用户未安装手机端，或入口无法打开。',
  'usageInstallFailed': '安装失败，请检查手机安装确认；签名不一致时不要直接卸载已有数据。',
  'usageSaveFailed': '电脑快照读写失败，请重试。',
  'usageUserChanged': '同步期间 Android 用户发生变化，请重新同步。',
};

const usageEn = {
  'usageTitle': 'Usage time',
  'usageIntro':
      'Read system daily statistics on demand over ADB. App names and icons reuse the app list cache.',
  'usageInstall': 'Install companion',
  'usageOpen': 'Open companion',
  'usageSync': 'Sync usage',
  'usageClear': 'Clear local snapshot',
  'usageSetupHint':
      'Enable ADB sharing in the companion and grant usage access in phone settings, then sync.',
  'usageEmpty':
      'No snapshot yet. Install the companion, grant access, then sync.',
  'usageBucketNote':
      'Queries today on the phone; Android may expand this to system daily buckets shown below. Screen time means interactive display time; foreground app times may overlap. Data can lag and is not an exact calendar-day or Digital Wellbeing report.',
  'usageScreen': 'Screen interactive time',
  'usageCombined': 'Combined app foreground time (may overlap)',
  'usageUnavailable': 'Not provided by system',
  'usageRange': 'Statistics range',
  'usageSnapshotTime': 'Snapshot generated',
  'usageDeviceTime': 'Phone time zone',
  'usageAndroidUser': 'Android user',
  'usageCachedNote':
      'Last saved snapshot, not live data. Failed syncs preserve this snapshot.',
  'usageNoApps':
      'Statistics returned with no apps having positive foreground time.',
  'usageSyncDone': 'Synced and saved on this computer.',
  'usageCacheCleared': 'Local snapshot cleared.',
  'usageSharingDisabled':
      'ADB sharing has not been enabled or is paused on the phone.',
  'usagePermissionRequired':
      'Grant usage access to the companion in phone settings.',
  'usageUserLocked': 'Unlock the phone once after restarting, then sync.',
  'usageNoData': 'No statistics returned. This does not mean zero usage.',
  'usageReadFailed': 'Read failed. Check the companion and retry.',
  'usageInvalidResponse':
      'Invalid or incompatible companion response. Check or update the companion.',
  'usageConnectionFailed':
      'ADB communication failed. Check the connection and retry.',
  'usageCompanionMissing':
      'Companion not installed for the current Android user, or cannot be opened.',
  'usageInstallFailed':
      'Installation failed. Check phone confirmation; do not uninstall existing data to resolve a signature mismatch.',
  'usageSaveFailed': 'Could not read or save the local snapshot. Please retry.',
  'usageUserChanged': 'Android user changed during sync. Please sync again.',
};
