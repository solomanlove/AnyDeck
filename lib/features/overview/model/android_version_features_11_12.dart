import 'android_version_distribution_data.dart';

/// Android 12 (S) 官方特性列表（中英双语对照）
/// 涵盖 New features, Behavior changes, Security and privacy, Large screen support (12L)
const List<AndroidFeatureSection> kAndroid12Features = [
  // 左侧列第 1 项：New features
  AndroidFeatureSection(
    title: 'New features',
    titleZh: '新特性与功能',
    columnIndex: 0,
    items: [
      'Material You',
      'Redesigned widgets',
      'Game Mode',
      'Rich content insertion',
      'AppSearch API',
      'Compatible media transcoding',
      'Improved notifications',
    ],
    itemsZh: [
      'Material You 动态色彩个性化设计语言',
      '全新设计规范的桌面微件',
      '游戏模式 (Game Mode) API 支持',
      '富媒体内容统一插入接口 (OnReceiveContentListener)',
      'AppSearch 本地高性能设备搜索引擎',
      '兼容媒体转码 (HEVC 动态转码为 AVC)',
      '通知中心视觉与交互体验升级',
    ],
  ),
  // 左侧列第 2 项：Behavior changes
  AndroidFeatureSection(
    title: 'Behavior changes',
    titleZh: '系统行为变更',
    columnIndex: 0,
    items: [
      'Performance Classes',
      'Stretch overscroll',
      'App splash screens',
      'Restricted App Standby Bucket',
      'Improved refresh rate switching',
      'Passpoint updates',
    ],
    itemsZh: [
      '性能等级标准 (Performance Class) 定义',
      '弹性拉伸过度滚动 (Stretch overscroll) 果冻特效',
      '系统级标准化应用启动画面 API (SplashScreen)',
      '新增受限应用待机分组 (Restricted Standby Bucket)',
      '更平滑的自适应屏幕刷新率切换机制',
      'Passpoint Wi-Fi 漫游协议功能扩展',
    ],
  ),
  // 左侧列第 3 项：Security and privacy
  AndroidFeatureSection(
    title: 'Security and privacy',
    titleZh: '安全与隐私保护',
    columnIndex: 0,
    items: [
      'App hibernation',
      'Nearby device permissions',
      'Approximate location',
      'Bluetooth permissions',
      'Permission group lookup',
      'Clipboard access notifications',
      'Permission package visibility',
    ],
    itemsZh: [
      '长期未使用的应用自动休眠 (App hibernation)',
      '附近设备发现运行时权限体系',
      '大致位置模糊定位权限 (Approximate location)',
      '免除精细位置依赖的全新蓝牙权限体系',
      '权限组定义反向查询接口',
      '剪贴板内容读取提示通知 (Toast)',
      '权限包可见性安全过滤',
    ],
  ),
  // 右侧列第 1 项：Large screen support (12L)
  AndroidFeatureSection(
    title: 'Large screen support (12L)',
    titleZh: '大屏幕设备支持 (Android 12L)',
    columnIndex: 1,
    items: [
      'System UI optimizations',
      'App taskbar',
      'Drag and drop an app into split-screen mode',
      'fast app-switching',
      'Visual and stability improvements to compatibility mode',
      'Activity embedding with Jetpack WindowManager',
    ],
    itemsZh: [
      '针对折叠屏与平板的系统级界面深度优化',
      '大屏专属常驻应用任务栏 (Taskbar)',
      '拖拽应用图标直接进入分屏多任务模式',
      '快捷应用切换手势与动画',
      '兼容模式 (Compatibility Mode) 视觉与稳定性改进',
      '基于 Jetpack WindowManager 的 Activity 嵌入双栏',
    ],
  ),
];

/// Android 11 (R) 官方特性列表（中英双语对照）
/// 涵盖 New features, Behavior changes, Security and privacy
const List<AndroidFeatureSection> kAndroid11Features = [
  // 左侧列第 1 项：New features
  AndroidFeatureSection(
    title: 'New features',
    titleZh: '新特性与功能',
    columnIndex: 0,
    items: [
      'Chat Bubbles',
      'Conversation improvements',
      'Wireless debugging',
      'Neural Networks API 1.3',
      'Frame rate API',
    ],
    itemsZh: [
      '对话气泡 (Chat Bubbles) 多任务悬浮窗',
      '通知栏专属对话空间与重要联系人置顶',
      '无线 ADB 调试功能 (Wireless debugging)',
      '神经网络计算 API (NNAPI) 1.3',
      'Surface 帧率设置 API (setFrameRate)',
    ],
  ),
  // 左侧列第 2 项：Behavior changes
  AndroidFeatureSection(
    title: 'Behavior changes',
    titleZh: '系统行为变更',
    columnIndex: 0,
    items: [
      'Exposure Notifications',
      'Conscrypt SSL engine by default',
      'Non-SDK interface restrictions',
      'URI access permissions requirements',
    ],
    itemsZh: [
      '暴露通知 (Exposure Notifications) 框架',
      '默认采用 Conscrypt 作为系统 SSL 引擎',
      '非 SDK 接口访问名单进一步限制加固',
      'Content URI 访问权限声明与授权规范强化',
    ],
  ),
  // 右侧列第 1 项：Security and privacy
  AndroidFeatureSection(
    title: 'Security and privacy',
    titleZh: '安全与隐私保护',
    columnIndex: 1,
    items: [
      'Scoped storage enforcement',
      'One-time permissions',
      'Permissions auto-reset',
      'Background location access',
      'Package visibility',
      'Foreground services',
      'Secure sharing of large datasets',
    ],
    itemsZh: [
      '分区存储 (Scoped Storage) 机制强制执行',
      '单次授权权限 (One-time permissions)',
      '长期未使用的应用权限自动重置',
      '后台位置访问权限与前台权限独立分离请求',
      '软件包可见性精细化控制 (<queries> 标签)',
      '前台服务摄像头与麦克风类型访问限制',
      '基于 BlobStoreManager 的大数据集安全跨应用共享',
    ],
  ),
];
