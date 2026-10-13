import 'android_version_distribution_data.dart';

/// Android 8.1 (Oreo) 官方特性列表（中英双语对照）
/// 涵盖 System, User Interface, Media, Security & Privacy
const List<AndroidFeatureSection> kAndroid81Features = [
  // 开发影响与适配要求（置顶展示）
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'Android Go optimizations: Memory-limited devices require slimmed memory profiles, RAM checks, and optimized APK size.',
      'SharedMemory API: Direct inter-process shared memory allocation and permission mapping.',
      'Safe Browsing programmatic check: WebView detects malicious URLs and allows custom programmatic fallback actions.',
    ],
    itemsZh: [
      'Android Go 轻量级设备优化：针对 1GB 及以下低运存设备需做好内存配额控制、RAM 分配检测及安装包精简。',
      'SharedMemory 跨进程共享内存：底层支持安全高效映射匿名共享内存，提升 IPC 大数据交互性能。',
      '安全浏览代码级接入：WebView 自动检测恶意网址并支持在代码中拦截与自定义响应策略。',
    ],
  ),
  // 左侧列第 1 项：System
  AndroidFeatureSection(
    title: 'System',
    titleZh: '系统特性与底层技术',
    columnIndex: 0,
    items: [
      'Android Go',
      'Neural Networks API',
      'Programmatic Safe Browsing actions',
      'Shared memory API',
    ],
    itemsZh: [
      'Android Go 轻量级系统内存优化与配置',
      '神经网络 API (NNAPI) 初始版本发布',
      '代码级安全浏览 (Safe Browsing) 响应控制',
      '进程间共享内存 API (SharedMemory)',
    ],
  ),
  // 左侧列第 2 项：User Interface
  AndroidFeatureSection(
    title: 'User Interface',
    titleZh: '用户界面与交互',
    columnIndex: 0,
    items: [
      'Improved Notifications',
      'EditText update',
      'WallpaperColors API',
    ],
    itemsZh: [
      '通知中心细节与通知音提示频率优化',
      'EditText 自动填充与输入体验更新',
      '壁纸主要颜色提取 API (WallpaperColors)',
    ],
  ),
  // 左侧列第 3 项：Media
  AndroidFeatureSection(
    title: 'Media',
    titleZh: '多媒体技术',
    columnIndex: 0,
    items: [
      'Video thumbnail extractor',
    ],
    itemsZh: [
      '原生高效视频缩略图提取器支持',
    ],
  ),
  // 右侧列第 1 项：Security & Privacy
  AndroidFeatureSection(
    title: 'Security & Privacy',
    titleZh: '安全与隐私保护',
    columnIndex: 1,
    items: [
      'Fingerprint updates',
      'Cryptography updates',
    ],
    itemsZh: [
      '指纹识别流程与多次尝试锁定提示优化',
      '加密算法更新与 Conscrypt 密码学加固',
    ],
  ),
];

/// Android 8.0 (Oreo) 官方特性列表（中英双语对照）
/// 涵盖 System, User Interface, Media, Wireless & Connectivity, Security & Privacy, Runtime & Tools
const List<AndroidFeatureSection> kAndroid80Features = [
  // 开发影响与适配要求（置顶展示）
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'Notification Channels mandatory: Apps must assign every notification to a channel; notifications without valid channels are dropped.',
      'Background execution limits: Background services cannot run indefinitely; must transition to JobScheduler or foreground services with ongoing notifications.',
      'Implicit broadcast restrictions: Most implicit broadcasts cannot be statically registered in manifest.',
      'Adaptive Icons: App launcher icons must provide background and foreground layers to match OEM mask shapes.',
    ],
    itemsZh: [
      '通知渠道 (Notification Channels) 强制要求：所有通知必须指定有效的渠道 ID，否则将被系统直接丢弃。',
      '后台执行与 Service 严格限制：应用退入后台数分钟后禁止启动后台 Service，传统后台轮询必须全面迁移至 JobScheduler 或带有常驻通知的前台服务。',
      '限制静态隐式广播：大部分隐式广播无法在清单中静态注册（如网络状态变化），必须在运行时动态注册。',
      '自适应图标 (Adaptive Icons)：图标必须分为前景与背景双层资源，以适配各大厂商不同裁切形状。',
    ],
  ),
  // 左侧列第 1 项：System
  AndroidFeatureSection(
    title: 'System',
    titleZh: '系统特性与底层技术',
    columnIndex: 0,
    items: [
      'Custom data store',
      'JobScheduler improvements',
      'Cached data',
    ],
    itemsZh: [
      '首选项自定义数据存储 (PreferenceDataStore)',
      'JobScheduler 任务执行与队列约束增强',
      '系统缓存数据透明配额与自动清理策略',
    ],
  ),
  // 左侧列第 2 项：User Interface
  AndroidFeatureSection(
    title: 'User Interface',
    titleZh: '用户界面与交互',
    columnIndex: 0,
    items: [
      'Picture-in-Picture mode',
      'Improved Notifications',
      'Autofill framework',
      'Downloadable fonts',
      'Multi-display support',
      'Adaptive icons',
    ],
    itemsZh: [
      '手机与平板画中画模式 (Picture-in-Picture)',
      '通知渠道 (Notification Channels) 与角标点',
      '系统级自动填充框架 (Autofill Framework)',
      '可下载字体 (Downloadable Fonts) 与 XML 字体',
      '多显示屏扩展与独立 Activity 栈支持',
      '自适应异形应用图标 (Adaptive Icons)',
    ],
  ),
  // 左侧列第 3 项：Media
  AndroidFeatureSection(
    title: 'Media',
    titleZh: '多媒体技术',
    columnIndex: 0,
    items: [
      'VolumeShaper',
      'Audio focus enhancements',
      'Media metrics',
      'MediaPlayer and MediaRecorder improvements',
      'Improved media file access',
    ],
    itemsZh: [
      '音量整形器 (VolumeShaper 淡入淡出特效)',
      '音频焦点延迟获取与混音行为增强',
      'MediaMetrics 媒体播放分析指标采集',
      'MediaPlayer 与 MediaRecorder 性能与格式优化',
      'Storage Access Framework 媒体访问优化',
    ],
  ),
  // 左侧列第 4 项：Wireless & Connectivity
  AndroidFeatureSection(
    title: 'Wireless & Connectivity',
    titleZh: '无线与连接',
    columnIndex: 0,
    items: [
      'Wi-Fi Aware',
      'Bluetooth updates',
      'Companion device pairing',
    ],
    itemsZh: [
      'Wi-Fi Aware (NAN) 邻近设备无网直连通信',
      '蓝牙 5.0 与 Sony LDAC 高品质音频编解码',
      '配套设备配对管理器 (CompanionDeviceManager)',
    ],
  ),
  // 右侧列第 1 项：Security & Privacy
  AndroidFeatureSection(
    title: 'Security & Privacy',
    titleZh: '安全与隐私保护',
    columnIndex: 1,
    items: [
      'New permissions',
      'New account access and discovery APIs',
    ],
    itemsZh: [
      '安装未知来源应用单项授权管控',
      '全新账户访问授权与发现 API',
    ],
  ),
  // 右侧列第 2 项：Runtime & Tools
  AndroidFeatureSection(
    title: 'Runtime & Tools',
    titleZh: '运行时与开发工具',
    columnIndex: 1,
    items: [
      'Platform optimizations',
      'Updated Java language support',
      'Updated ICU4J Android Framework APIs',
    ],
    itemsZh: [
      '系统启动耗时与并发性能底层深度优化',
      'Java 8 语言特性与常用 API 原生支持',
      '升级至 ICU 58 的国际化 Framework API',
    ],
  ),
];

/// Android 7.1 (Nougat) 官方特性列表（中英双语对照）
/// 涵盖 System, VR, User Interface, User Input, Wireless & Connectivity, Wear
const List<AndroidFeatureSection> kAndroid71Features = [
  // 开发影响与适配要求（置顶展示）
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'App Shortcuts API: Static and dynamic deep-link launcher shortcuts revealed upon long-pressing app icon.',
      'Circular icon resources: android:roundIcon attribute allows providing round launcher icons for Pixel/OEM devices.',
      'Commit Content API: Soft keyboards can send rich media (GIFs, stickers, custom images) directly to apps.',
    ],
    itemsZh: [
      'App Shortcuts 桌面快捷方式：支持静态与动态桌面深层链接快捷入口，用户长按桌面图标即可触发快捷操作。',
      '圆形图标资源 (Round Icon)：支持通过 android:roundIcon 为特定桌面启动器提供专属圆形图标适配。',
      '提交富内容输入法接口 (Commit Content API)：输入法可直接将动图 (GIF)、表情包与富媒体素材安全发送给应用。',
    ],
  ),
  // 左侧列第 1 项：System
  AndroidFeatureSection(
    title: 'System',
    titleZh: '系统特性与底层技术',
    columnIndex: 0,
    items: [
      'Enhanced Live Wallpaper Metadata',
      'Storage Manager Intent',
      'Demo User Hint',
    ],
    itemsZh: [
      '动态壁纸元数据扩展与预览接口',
      '存储管理器清理意图 (ACTION_MANAGE_STORAGE)',
      '演示模式零售展示用户提示 API',
    ],
  ),
  // 左侧列第 2 项：VR
  AndroidFeatureSection(
    title: 'VR',
    titleZh: '虚拟现实 (VR)',
    columnIndex: 0,
    items: [
      'Improved VR Thread Scheduling',
    ],
    itemsZh: [
      'Daydream 高优先级 VR 专属线程调度优化',
    ],
  ),
  // 左侧列第 3 项：User Interface
  AndroidFeatureSection(
    title: 'User Interface',
    titleZh: '用户界面与交互',
    columnIndex: 0,
    items: [
      'App Shortcuts',
      'Round Icon Resources',
    ],
    itemsZh: [
      '应用快捷方式 (App Shortcuts 长按弹出菜单)',
      '圆形应用图标资源专用配置支持',
    ],
  ),
  // 左侧列第 4 项：User Input
  AndroidFeatureSection(
    title: 'User Input',
    titleZh: '用户输入体验',
    columnIndex: 0,
    items: [
      'Image Keyboard Support',
      'New Professional Emoji',
    ],
    itemsZh: [
      '输入法富媒体图片插入接口 (CommitContent)',
      '新增职业与多样化 Emoji 表情符号支持',
    ],
  ),
  // 右侧列第 1 项：Wireless & Connectivity
  AndroidFeatureSection(
    title: 'Wireless & Connectivity',
    titleZh: '无线与网络通信',
    columnIndex: 1,
    items: [
      'APIs for Carriers and Calling Apps',
    ],
    itemsZh: [
      '运营商配置与网络通话应用专用 API',
    ],
  ),
  // 右侧列第 2 项：Wear
  AndroidFeatureSection(
    title: 'Wear',
    titleZh: '可穿戴设备支持 (Wear)',
    columnIndex: 1,
    items: [
      'New Screen Densities for Wear Devices',
    ],
    itemsZh: [
      'Wear 智能手表专用屏幕像素密度规范',
    ],
  ),
];
