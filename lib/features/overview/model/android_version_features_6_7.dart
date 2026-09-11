import 'android_version_distribution_data.dart';

/// Android 7.0 (Nougat) 官方特性列表（中英双语对照）
/// 涵盖 User Interface, Performance, Battery Life, Wireless & Connectivity, Graphics, System,
/// Android for Work, Accessiblity, Security, VR, Printing Framework
const List<AndroidFeatureSection> kAndroid70Features = [
  // 左侧列第 1 项：User Interface
  AndroidFeatureSection(
    title: 'User Interface',
    titleZh: '用户界面与多任务',
    columnIndex: 0,
    items: [
      'Multi-window Support',
      'Notifications',
      'Quick Settings Tile API',
      'Custom Pointer API',
    ],
    itemsZh: [
      '分屏多窗口模式 (Multi-window Support)',
      '全新通知样式、分组与直接回复 (Direct Reply)',
      '快捷设置图块 API (Quick Settings Tile API)',
      '自定义鼠标指针图标 API (Custom Pointer API)',
    ],
  ),
  // 左侧列第 2 项：Performance
  AndroidFeatureSection(
    title: 'Performance',
    titleZh: '系统性能与编译优化',
    columnIndex: 0,
    items: [
      'Profile-guided JIT/AOT Compilation',
      'Quick Path to App Install',
      'Sustained Performance API',
      'Frame Metrics API',
    ],
    itemsZh: [
      '配置文件引导的 JIT/AOT 混合编译架构',
      '应用极速安装路径 (无需漫长预编译)',
      '持续性能 API (Sustained Performance API)',
      'UI 掉帧与渲染耗时指标 API (FrameMetrics)',
    ],
  ),
  // 左侧列第 3 项：Battery Life
  AndroidFeatureSection(
    title: 'Battery Life',
    titleZh: '电池续航与后台能效',
    columnIndex: 0,
    items: [
      'Doze on the Go',
      'Project Svelte: Background Optimizations',
      'SurfaceView',
    ],
    itemsZh: [
      '移动低电耗模式 (Doze on the Go 熄屏即省电)',
      'Project Svelte 后台内存占用深度优化',
      'SurfaceView 异步渲染与更佳功耗表现',
    ],
  ),
  // 左侧列第 4 项：Wireless & Connectivity
  AndroidFeatureSection(
    title: 'Wireless & Connectivity',
    titleZh: '无线与数据连接',
    columnIndex: 0,
    items: [
      'Data Saver',
      'Number Blocking',
      'Call Screening',
    ],
    itemsZh: [
      '流量节省程序 (Data Saver) 系统级支持',
      '系统级电话号码拦截框架',
      '来电筛选与垃圾电话识别过滤服务',
    ],
  ),
  // 左侧列第 5 项：Graphics
  AndroidFeatureSection(
    title: 'Graphics',
    titleZh: '图形渲染技术',
    columnIndex: 0,
    items: [
      'Vulkan API',
    ],
    itemsZh: [
      'Vulkan 低开销高性能 3D 图形 API 首发',
    ],
  ),
  // 左侧列第 6 项：System
  AndroidFeatureSection(
    title: 'System',
    titleZh: '系统特性与底层平台',
    columnIndex: 0,
    items: [
      'Direct Boot',
      'Multi-locale Support, More Languages',
      'ICU4J APIs in Android',
      'APK Signature Scheme v2',
      'Scoped Directory Access',
      'Keyboard Shortcuts Helper',
      'Virtual Files',
    ],
    itemsZh: [
      '直接开机模式 (Direct Boot 设备加密支持)',
      '多语言偏好设置与多区域回退机制',
      'Android Framework 原生内置 ICU4J API',
      'APK 签名方案 v2 (全文件哈希校验更安全)',
      '作用域目录访问限制 (Scoped Directory Access)',
      '实体键盘快捷键辅助查看器 (Cmd+/)',
      '虚拟文件支持 (SAF 只读流协议)',
    ],
  ),
  // 右侧列第 1 项：Android for Work
  AndroidFeatureSection(
    title: 'Android for Work',
    titleZh: '企业级支持 (Android for Work)',
    columnIndex: 1,
    items: [
      'Work profile security challenge',
      'Turn off work',
      'Always on VPN',
      'Customized provisioning',
    ],
    itemsZh: [
      '工作资料独立安全凭据与锁屏验证',
      '一键暂停关闭工作资料与休假模式',
      '始终开启的 VPN (Always on VPN)',
      '企业定制化设备配置部署流程',
    ],
  ),
  // 右侧列第 2 项：Accessiblity (保留截图官方拼写)
  AndroidFeatureSection(
    title: 'Accessiblity',
    titleZh: '无障碍辅助功能',
    columnIndex: 1,
    items: [
      'Vision Settings on the Welcome screen',
    ],
    itemsZh: [
      '开机欢迎屏幕视力无障碍设置引导',
    ],
  ),
  // 右侧列第 3 项：Security
  AndroidFeatureSection(
    title: 'Security',
    titleZh: '系统安全',
    columnIndex: 1,
    items: [
      'Key Attestation',
      'Network Security Config',
      'Default Trusted Certificate Authority',
    ],
    itemsZh: [
      '硬件级密钥证书认证 (Key Attestation)',
      '网络安全配置文件 (Network Security Config)',
      '应用默认仅信任系统内置 CA 根证书',
    ],
  ),
  // 右侧列第 4 项：VR
  AndroidFeatureSection(
    title: 'VR',
    titleZh: '虚拟现实 (VR)',
    columnIndex: 1,
    items: [
      'Platform support and optimizations for VR Mode',
    ],
    itemsZh: [
      'Daydream 高性能 VR 模式系统底层优化',
    ],
  ),
  // 右侧列第 5 项：Printing Framework
  AndroidFeatureSection(
    title: 'Printing Framework',
    titleZh: '打印框架',
    columnIndex: 1,
    items: [
      'Print service enhancements',
    ],
    itemsZh: [
      '系统打印服务与自定义排队监控能力增强',
    ],
  ),
];

/// Android 6.0 (Marshmallow) 官方特性列表（中英双语对照）
/// 涵盖 Security, System, Multimedia, User Input, User Interface, Wireless & Connectivity, Android for Work
const List<AndroidFeatureSection> kAndroid60Features = [
  // 左侧列第 1 项：Security
  AndroidFeatureSection(
    title: 'Security',
    titleZh: '安全特性',
    columnIndex: 0,
    items: [
      'Fingerprint Authentication',
      'Confirm Credential',
    ],
    itemsZh: [
      '原生指纹识别认证 API (FingerprintManager)',
      '确认设备锁屏凭据 API (Confirm Credential)',
    ],
  ),
  // 左侧列第 2 项：System
  AndroidFeatureSection(
    title: 'System',
    titleZh: '系统特性',
    columnIndex: 0,
    items: [
      'App Linking',
      'Adoptable Storage Devices',
    ],
    itemsZh: [
      '深层链接域名自动验证 (App Linking)',
      '外部存储设备合并为内部存储 (Adoptable Storage)',
    ],
  ),
  // 左侧列第 3 项：Multimedia
  AndroidFeatureSection(
    title: 'Multimedia',
    titleZh: '多媒体技术',
    columnIndex: 0,
    items: [
      '4K Display Mode',
      'Support for MIDI',
      'Create digital audio capture and playback objects',
      'APIs to associate audio and input devices',
      'List of all audio devices',
      'Updated video processing APIs',
      'Flashlight API',
      'Reprocessing Camera2 API',
      'Updated ImageWriter objects and Image Reader class',
    ],
    itemsZh: [
      '4K 超高清显示渲染模式支持',
      '原生 MIDI 电子乐器协议支持',
      '创建数字音频捕获与回放核心对象',
      '音频设备与输入设备智能关联绑定 API',
      '枚举查询所有连接音频外设列表',
      '更新的视频处理与软硬件混合解码 API',
      '相机闪光灯/手电筒控制 API (CameraManager)',
      'Camera2 YUV/RAW 图像后处理管道 API',
      'ImageWriter 与 ImageReader 异步数据流升级',
    ],
  ),
  // 左侧列第 4 项：User Input
  AndroidFeatureSection(
    title: 'User Input',
    titleZh: '用户输入与语音交互',
    columnIndex: 0,
    items: [
      'Voice Interactions',
      'Assist API',
      'Bluetooth Stylus Support',
    ],
    itemsZh: [
      '语音交互会话 API (VoiceInteractionSession)',
      '屏幕上下文助手 API (Assist API / Now on Tap)',
      '蓝牙智能手写笔压感与功能按键支持',
    ],
  ),
  // 右侧列第 1 项：User Interface
  AndroidFeatureSection(
    title: 'User Interface',
    titleZh: '用户界面',
    columnIndex: 1,
    items: [
      'Themeable ColorStateLists',
    ],
    itemsZh: [
      '支持主题属性解析的颜色状态列表 (ColorStateLists)',
    ],
  ),
  // 右侧列第 2 项：Wireless & Connectivity
  AndroidFeatureSection(
    title: 'Wireless & Connectivity',
    titleZh: '无线与数据连接',
    columnIndex: 1,
    items: [
      'Hotspot 2.0',
      'Improved Bluetooth Low Energy Scanning',
    ],
    itemsZh: [
      'Hotspot 2.0 (Release 1) 自动 Wi-Fi 漫游认证',
      '低功耗蓝牙 (BLE) 高能效扫描过滤机制',
    ],
  ),
  // 右侧列第 3 项：Android for Work
  AndroidFeatureSection(
    title: 'Android for Work',
    titleZh: '企业级支持 (Android for Work)',
    columnIndex: 1,
    items: [
      'Controls for Corporate-Owned, Single-Use devices',
      'Silent install and uninstall of apps by Device Owner',
      'Silent enterprise certificate access',
      'Auto-acceptance of system updates',
      'Delegated certificate installation',
      'Data usage tracking',
      'Runtime permission management',
      'Work status notification',
    ],
    itemsZh: [
      '企业单用途设备 (COSU/Kiosk) 严格锁定控制',
      '设备所有者静默安装与卸载企业应用',
      '企业客户端证书免弹窗静默访问授权',
      '企业策略自动接受并应用系统 OTA 更新',
      '委托第三方应用代为安装安全证书',
      '分工作空间网络流量统计与监控',
      '企业策略托管运行时权限动态授权',
      '工作资料激活状态通知与图标徽标',
    ],
  ),
];
