/// 使用时长最小闭环文案；统计口径与授权说明中英文保持一致。
const usageZh = {
  'usageTitle': '使用时长',
  'usageIntro': '通过 ADB 同步手机记录到电脑历史库。使用统计与位置分别授权和同步。',
  'usageInstall': '安装手机端',
  'usageOpen': '打开手机端',
  'usageSync': '同步使用时长',
  'usageClear': '清除当前来源的电脑历史',
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
  'usageCachedNote': '显示所选查询日最后入库的系统统计，非实时数据；不叠加同一天的多份快照。',
  'usageNoApps': '系统返回了统计，但没有正时长的 App 记录。',
  'usageSyncDone': '已同步并保存到电脑。',
  'usageCacheCleared': '当前来源的电脑历史已清除；手机尚未过期的数据可重新同步。',
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
  'historyCursorInvalid': '手机历史游标不一致，请检查是否清理过手机数据。',
  'historyUpdateRequired': '请先安装新版手机端，再同步历史记录。',
  'historyMorePending': '已保存部分历史，请再次同步继续导入。',
  'historyGap': '部分手机记录在同步前已过期，历史可能存在缺口。',
  'locationTitle': '位置历史',
  'locationSync': '同步位置记录',
  'locationEmpty': '没有已同步的位置。请在手机端开启位置共享、授权并开始记录，收到定位后再同步。',
  'locationCachedNote': '以下为已同步的历史位置，不代表此刻位置。时间按电脑时区显示。',
  'locationLatest': '最后已知位置采集时间',
  'locationAccuracy': '精度半径',
  'locationMock': '模拟位置',
  'locationMap': '在 OpenStreetMap 查看此坐标（联网）',
  'locationMapFailed': '无法打开地图，请检查默认浏览器。',
  'locationTrailNote':
      '按经纬度显示当天位置和轨迹（最近 1000 点）。拖动或滚轮缩放地图；底图需要联网，超过 30 分钟的缺口不连线。',
  'locationMapLatest': '所选日期最后一个位置',
  'locationMapZoomIn': '放大地图',
  'locationMapZoomOut': '缩小地图',
  'locationMapFit': '显示当天全部轨迹',
  'locationMapRetry': '重试底图',
  'locationTilesFailed': '部分地图底图加载失败，请检查网络后重试。',
  'locationMapAttribution': 'OpenStreetMap 贡献者',
  'cameraTitle': '摄像头',
  'cameraIntro': '手动开始实时画面，手机保留系统摄像头使用提示。只传画面，不采集声音、不录像；切页或关闭弹窗即停止。',
  'cameraBack': '后置镜头',
  'cameraFront': '前置镜头',
  'cameraStart': '开始预览',
  'cameraStop': '停止预览',
  'cameraIdle': '点击开始，在此显示摄像头画面。',
  'cameraStarting': '正在连接摄像头…',
  'cameraWaitingFrame': '已连接，等待画面…',
  'cameraLive': '摄像头预览中（无声音）',
  'cameraStopping': '正在停止…',
  'cameraStopped': '摄像头已停止。',
  'cameraDisconnected': '设备连接或摄像头视频流已断开，预览已停止。',
  'cameraStartFailed': '摄像头启动或画面读取失败，请检查连接、镜头占用和手机权限后重试。',
  'cameraStopFailed': '预览清理失败，请检查手机摄像头是否已停止。',
  'cameraAndroidRequired': '摄像头预览需要 Android 12 或更高版本。',
  'cameraPlatformRequired': '当前内嵌摄像头预览仅支持 macOS。',
};

const usageEn = {
  'usageTitle': 'Usage time',
  'usageIntro':
      'Sync phone records to the local history database over ADB. Usage and location are authorized and synced separately.',
  'usageInstall': 'Install companion',
  'usageOpen': 'Open companion',
  'usageSync': 'Sync usage',
  'usageClear': 'Clear this source’s local history',
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
      'Last imported system report for the selected query day, not live data. Multiple snapshots of a day are not added together.',
  'usageNoApps':
      'Statistics returned with no apps having positive foreground time.',
  'usageSyncDone': 'Synced and saved on this computer.',
  'usageCacheCleared':
      'Local history cleared. Unexpired phone records can be synced again.',
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
  'historyCursorInvalid':
      'Phone history cursor mismatch. Check whether phone data was cleared.',
  'historyUpdateRequired':
      'Install the updated companion before syncing history.',
  'historyMorePending':
      'Partial history saved. Sync again to continue importing.',
  'historyGap':
      'Some phone records expired before sync. History may have gaps.',
  'locationTitle': 'Location history',
  'locationSync': 'Sync locations',
  'locationEmpty':
      'No synced locations. Enable location sharing on the phone, grant access and start recording; sync after a fix is received.',
  'locationCachedNote':
      'Synced historical locations, not current location. Times use the computer’s time zone.',
  'locationLatest': 'Last known location captured',
  'locationAccuracy': 'Accuracy radius',
  'locationMock': 'Mock location',
  'locationMap': 'View this coordinate on OpenStreetMap (online)',
  'locationMapFailed': 'Could not open the map. Check the default browser.',
  'locationTrailNote':
      'Daily locations and trail (latest 1000 points). Drag or scroll to zoom; map tiles require internet. Gaps over 30 minutes are not connected.',
  'locationMapLatest': 'Last location on the selected date',
  'locationMapZoomIn': 'Zoom in',
  'locationMapZoomOut': 'Zoom out',
  'locationMapFit': 'Fit daily trail',
  'locationMapRetry': 'Retry map tiles',
  'locationTilesFailed':
      'Some map tiles failed to load. Check your connection and retry.',
  'locationMapAttribution': 'OpenStreetMap contributors',
  'cameraTitle': 'Camera',
  'cameraIntro':
      'Start a live preview manually; Android camera indicators remain visible. Video only, no audio or recording. Switching tabs or closing stops the camera.',
  'cameraBack': 'Back camera',
  'cameraFront': 'Front camera',
  'cameraStart': 'Start preview',
  'cameraStop': 'Stop preview',
  'cameraIdle': 'Start to view the camera here.',
  'cameraStarting': 'Connecting to camera…',
  'cameraWaitingFrame': 'Connected; waiting for video…',
  'cameraLive': 'Camera preview active (no audio)',
  'cameraStopping': 'Stopping…',
  'cameraStopped': 'Camera stopped.',
  'cameraDisconnected':
      'Device or camera stream disconnected. Preview stopped.',
  'cameraStartFailed':
      'Camera start or video failed. Check the connection, camera availability and phone permissions, then retry.',
  'cameraStopFailed':
      'Preview cleanup failed. Check that the phone camera has stopped.',
  'cameraAndroidRequired': 'Camera preview requires Android 12 or later.',
  'cameraPlatformRequired':
      'Embedded camera preview currently supports macOS only.',
};
