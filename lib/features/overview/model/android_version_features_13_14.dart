import 'android_version_distribution_data.dart';

/// Android 14 (U) 官方特性列表（中英双语对照）
/// 涵盖 New features, Behavior changes, Security and privacy
const List<AndroidFeatureSection> kAndroid14Features = [
  // 开发影响与适配要求（置顶展示）
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    items: [
      'Foreground service types required: All foreground services must declare explicit types with matching manifest permissions, or startForeground fails.',
      'Explicit broadcast receiver export: Context-registered receivers must specify RECEIVER_EXPORTED or RECEIVER_NOT_EXPORTED.',
      'Selected photos access: Users can grant partial access to media files (READ_MEDIA_VISUAL_USER_SELECTED); apps must support partial selection gracefully.',
      'Minimum installable target API 23: Android blocks installation of apps targeting below API 23 (Android 6.0).',
      'Exact alarms denied by default: SCHEDULE_EXACT_ALARM is denied by default; apps must transition to inexact alarms or request USE_EXACT_ALARM.',
    ],
    itemsZh: [
      '强制声明前台服务类型：所有 Foreground Service 必须显式声明类型（如 dataSync, location 等）并申请对应权限，否则启动抛出异常。',
      '动态注册广播必须指定导出状态：代码注册广播接收器时必须显式传入 RECEIVER_EXPORTED 或 RECEIVER_NOT_EXPORTED，否则抛出 SecurityException。',
      '仅授权选定照片权限：用户可选择只授权访问部分照片与视频 (READ_MEDIA_VISUAL_USER_SELECTED)，需适配非全量授权的动态刷新场景。',
      '最低安装 API 级别限制：系统禁止安装 targetSdkVersion 低于 23 (Android 6.0) 的老旧应用。',
      '精准闹钟权限默认拒绝：SCHEDULE_EXACT_ALARM 权限默认不再自动授予，非核心计时/日历应用需适配非精准闹钟。',
    ],
  ),
  // 左侧列第 1 项：New features
  AndroidFeatureSection(
    title: 'New features',
    titleZh: '新特性与功能',
    items: [
      'Ultra HDR for images',
      'Zoom, Focus, Postview, and more in camera extensions',
      'Lossless USB audio',
      'Health Connect',
      'Add custom actions',
      'Custom meshes with vertex and fragment shaders',
    ],
    itemsZh: [
      '图像 Ultra HDR 格式支持',
      '相机扩展中的变焦、对焦、后期预览等增强',
      '无损 USB 音频传输支持',
      '健康数据连接 (Health Connect)',
      '系统级自定义快捷操作 (Custom Actions)',
      '基于顶点与片元着色器的自定义网格特效',
    ],
  ),
  // 左侧列第 2 项：Behavior changes
  AndroidFeatureSection(
    title: 'Behavior changes',
    titleZh: '系统行为变更',
    items: [
      'Foreground service types are required',
      'Enforcement of BLUETOOTH_CONNECT permission',
      'JobScheduler reinforces callback and network behavior',
      'Apps can kill only their own background processes',
      'Schedule exact alarms are denied by default',
      'Data safety information is more visible',
      'Minimum installable target API level',
    ],
    itemsZh: [
      '必须显式声明前台服务类型 (Foreground Service Types)',
      '强制执行 BLUETOOTH_CONNECT 蓝牙连接权限',
      'JobScheduler 回调与网络行为机制强化',
      '应用仅允许终止自身的后台进程',
      '精准闹钟权限 (Schedule exact alarms) 默认拒绝',
      '数据安全信息展示更直观',
      '设置最低可安装的目标 API 级别限制 (API 23+)',
    ],
  ),
  // 右侧列第 1 项：Security and privacy
  AndroidFeatureSection(
    title: 'Security and privacy',
    titleZh: '安全与隐私保护',
    items: [
      'Credential Manager',
      'Improvements for app stores',
      'Detect when users take device screenshots',
      'Secure full-screen Intent notifications',
      'Restrictions to implicit and pending intents',
      'Safer dynamic code loading',
      'restrictions on starting activities from the background',
      'User consent required for each MediaProjection',
    ],
    itemsZh: [
      '凭据管理器 (Credential Manager)',
      '第三方应用商店体验与权限优化',
      '屏幕截图事件检测 API',
      '更安全的全屏 Intent 通知',
      '隐式与 PendingIntent 调用限制',
      '更安全的动态代码加载机制',
      '后台启动 Activity 行为限制加固',
      '每次 MediaProjection 屏幕投影均需用户单独确认授权',
    ],
  ),
];

/// Android 13 (T) 官方特性列表（中英双语对照）
/// 涵盖 New features, Behavior changes, Security and privacy
const List<AndroidFeatureSection> kAndroid13Features = [
  // 开发影响与适配要求（置顶展示）
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    items: [
      'Runtime notification permission: Apps must request POST_NOTIFICATIONS runtime permission before posting notifications to users.',
      'Granular media permissions: READ_EXTERNAL_STORAGE deprecated and split into READ_MEDIA_IMAGES, READ_MEDIA_VIDEO, and READ_MEDIA_AUDIO.',
      'System Photo Picker: Embedded system picker allows users to share media without granting any storage runtime permissions.',
      'Predictive back gesture opt-in: Apps can test and opt in to predictive back animations using android:enableOnBackInvokedCallback="true".',
      'Clipboard sensitive data auto-clearing: Password and sensitive clipboard items are automatically masked and cleared by the system.',
    ],
    itemsZh: [
      '通知运行时权限：必须在运行时向用户动态申请 POST_NOTIFICATIONS 权限后方可发送通知，否则所有通知被系统默默拦截。',
      '细分媒体权限替代旧版存储权限：废弃宽泛的 READ_EXTERNAL_STORAGE，拆分为 READ_MEDIA_IMAGES、READ_MEDIA_VIDEO 与 READ_MEDIA_AUDIO 独立细分权限。',
      '原生系统照片选择器 (Photo Picker)：系统级内嵌照片选择器，应用无需申请任何存储权限即可安全选取照片和视频。',
      '预测性返回手势启用：引入 enableOnBackInvokedCallback 配置，开启预测性返回动画并适配统一的返回导航回调。',
      '剪贴板敏感数据自动清理：系统剪贴板编辑器会在复制密码或敏感数据时进行系统级隐藏遮罩与定期自动清理。',
    ],
  ),
  // 左侧列第 1 项：New features
  AndroidFeatureSection(
    title: 'New features',
    titleZh: '新特性与功能',
    items: [
      'Tablet and large screen support',
      'Programmable shaders',
      'Color vector fonts',
      'Predictive back gesture',
      'Bluetooth LE Audio',
      'Splash screen efficiency improvements',
      'ART optimizations',
    ],
    itemsZh: [
      '平板电脑与大屏幕设备多任务体验升级',
      '可编程运行时着色器 (RuntimeShader)',
      '彩色矢量字体 (COLRv1) 标准支持',
      '预测性返回手势动画预览',
      '低功耗蓝牙音频 (Bluetooth LE Audio)',
      '应用启动画面 (Splash Screen) 效率与渲染优化',
      'ART 虚拟机底层性能优化',
    ],
  ),
  // 左侧列第 2 项：Behavior changes
  AndroidFeatureSection(
    title: 'Behavior changes',
    titleZh: '系统行为变更',
    items: [
      'OpenJDK 11 updates',
      'Battery Resource Utilization',
      'Media controls derived from PlaybackState',
      'Permission required for advertising ID',
      'Updated non-SDK restrictions',
    ],
    itemsZh: [
      'OpenJDK 11 核心库与工具更新',
      '电池资源使用率与前台服务配额优化',
      '基于 PlaybackState 衍生生成的统一媒体控制条',
      '访问广告 ID (Advertising ID) 需显式权限声明',
      '更新的非 SDK 接口访问限制名单',
    ],
  ),
  // 右侧列第 1 项：Security and privacy
  AndroidFeatureSection(
    title: 'Security and privacy',
    titleZh: '安全与隐私保护',
    items: [
      'Safer exporting of context-registered receivers',
      'Enhanced photo picker privacy',
      'New runtime permission for nearby Wi-Fi devices',
      'Exact alarms permission',
      'Developer downgradable permissions',
      'APK Signature Scheme v3.1',
      'Better error reporting in Keystore and KeyMint',
    ],
    itemsZh: [
      '上下文注册广播接收器的安全导出显式声明',
      '隐私增强的照片选择器 (Photo Picker)',
      '针对附近 Wi-Fi 设备的新增独立运行时权限',
      '精准闹钟权限细化控制 (SCHEDULE_EXACT_ALARM)',
      '开发者可主动撤销的无用运行时权限 API',
      'APK 签名方案 v3.1 支持',
      'Keystore 与 KeyMint 更完善的错误状态上报',
    ],
  ),
];
