import 'android_version_distribution_data.dart';

/// Android 10 (Q) 官方特性列表（中英双语对照）
/// 涵盖 System, User Interface, Camera and media, Security and privacy
const List<AndroidFeatureSection> kAndroid10Features = [
  // 开发影响与适配要求（置顶展示）
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'Scoped Storage introduced: Replaced raw external storage access with sandboxed spaces; opt-out requestLegacyExternalStorage available temporarily.',
      'Non-resettable device IDs blocked: Third-party apps cannot access IMEI, serial number, or MAC address; must migrate to OAID or UUID.',
      'Background Activity starts blocked: Apps in background cannot start Activities directly; must use high-priority notifications with full-screen intents.',
      'Background clipboard access blocked: Background apps cannot read clipboard data unless they are the default IME.',
      'System-wide Dark Theme: Apps must support DayNight themes and adapt color assets.',
    ],
    itemsZh: [
      '引入分区存储 (Scoped Storage)：首次引入沙盒化存储模型，限制对外部公共存储目录的随意读写，可临时使用 requestLegacyExternalStorage 过渡。',
      '禁用不可变设备硬件标识符：普通应用被禁止读取 IMEI、序列号与 MAC 地址，必须转用 OAID 或应用级 UUID。',
      '禁止后台直接启动 Activity：处于后台的应用无法直接拉起界面，必须通过发送高优先级通知配合 FullScreenIntent 引导用户交互。',
      '后台剪贴板读取拦截：后台应用无法窃取或读取剪贴板内容，仅前台获焦应用或默认输入法可访问。',
      '系统级深色模式 (Dark Theme)：系统全局支持暗色主题，应用必须适配 DayNight 主题资源与反色视觉。',
    ],
  ),
  // 左侧列第 1 项：System
  AndroidFeatureSection(
    title: 'System',
    titleZh: '系统特性与底层技术',
    columnIndex: 0,
    items: [
      'Foldables support',
      '5G support',
      'Gesture navigation',
      'ART optimizations',
      'Neural Networks API 1.2',
      'Thermal API',
    ],
    itemsZh: [
      '折叠屏设备多任务系统级支持',
      '5G 网络连接与状态感知支持',
      '全面屏手势导航 (Gesture navigation)',
      'ART 虚拟机性能优化与预编译加速',
      '神经网络 API (NNAPI) 1.2',
      '设备温度与热状态监控 API (Thermal API)',
    ],
  ),
  // 左侧列第 2 项：User Interface
  AndroidFeatureSection(
    title: 'User Interface',
    titleZh: '用户界面与交互',
    columnIndex: 0,
    items: [
      'Smart Reply in notifications',
      'Dark theme',
      'Settings panels',
      'Sharing shortcuts',
    ],
    itemsZh: [
      '通知中心智能回复与操作建议 (Smart Reply)',
      '系统级深色主题 (Dark theme)',
      '应用内浮层快捷设置面板 (Settings panels)',
      '分享快捷方式 (Sharing Shortcuts API)',
    ],
  ),
  // 左侧列第 3 项：Camera and media
  AndroidFeatureSection(
    title: 'Camera and media',
    titleZh: '相机与多媒体',
    columnIndex: 0,
    items: [
      'Dynamic depth for photos',
      'Audio playback capture',
      'New codecs',
      'Native MIDI API',
      'Vulkan everywhere',
      'Directional microphones',
    ],
    itemsZh: [
      '动态照片景深数据格式 (Dynamic Depth)',
      '音频播放内录捕获 API (Audio playback capture)',
      '新增 AV1 / Opus / HDR10+ 编解码器',
      '原生 C++ MIDI 音频接口 (Native MIDI API)',
      '系统级全面普及 Vulkan 1.1 图形渲染',
      '指向性麦克风与声音聚焦控制',
    ],
  ),
  // 右侧列第 1 项：Security and privacy
  AndroidFeatureSection(
    title: 'Security and privacy',
    titleZh: '安全与隐私保护',
    columnIndex: 1,
    items: [
      'New location permissions',
      'Storage encryption',
      'TLS 1.3 by default',
      'Platform hardening',
      'Improved biometrics',
    ],
    itemsZh: [
      '仅在使用应用期间允许的位置权限控制',
      'Adiantum 设备级文件存储加密标准',
      '系统默认启用 TLS 1.3 传输加密',
      '系统底层平台安全加固与沙盒限制',
      '生物识别安全框架升级与体验改进',
    ],
  ),
];

/// Android 9 (Pie) 官方特性列表（中英双语对照）
/// 涵盖 System, User Interface, Media, Security and privacy, Accessibility
const List<AndroidFeatureSection> kAndroid9Features = [
  // 开发影响与适配要求（置顶展示）
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'Non-SDK interface restrictions: Strict reflection and JNI greylists/blacklists; calling private platform APIs throws NoSuchMethodException.',
      'Cleartext HTTP blocked by default: Network security config blocks cleartext http:// traffic; apps must use https://.',
      'Display Cutout handling: Apps must handle display cutouts, notches, and status bar insets using layoutInDisplayCutoutMode.',
      'Background camera/mic idle: Idle background apps cannot access microphone, camera, or continuous sensors.',
    ],
    itemsZh: [
      '限制使用非 SDK 接口：系统建立黑白名单机制，严厉限制通过反射调用私有内部 API，违规调用直接抛出异常。',
      '默认禁止明文 HTTP 传输：网络安全配置默认禁用明文 HTTP 流量 (cleartextTrafficPermitted=false)，所有网络请求强制要求 HTTPS。',
      '刘海屏/凹口屏 (Display Cutout) 适配：引入 layoutInDisplayCutoutMode 属性，应用必须适配屏幕凹口安全边距。',
      '后台麦克风与相机静默：处于闲置后台的应用无法使用相机传感器与麦克风录音，传感器上报空数据以保护隐私。',
    ],
  ),
  // 左侧列第 1 项：System
  AndroidFeatureSection(
    title: 'System',
    titleZh: '系统特性与底层技术',
    columnIndex: 0,
    items: [
      'Indoor positioning with Wi-Fi RTT',
      'Multi-camera support',
      'Display cutout support',
    ],
    itemsZh: [
      '基于 Wi-Fi RTT 协议的室内精确定位',
      '多摄像头同时调用的原生 API 支持',
      '异形屏/刘海屏/挖孔屏适配 (Display cutout)',
    ],
  ),
  // 左侧列第 2 项：User Interface
  AndroidFeatureSection(
    title: 'User Interface',
    titleZh: '用户界面与交互',
    columnIndex: 0,
    items: [
      'Improved notifications',
      'Improved text support',
      'ImageDecoder and new animation classes',
    ],
    itemsZh: [
      '富媒体会话通知样式与快捷回复增强',
      '文本放大镜 (Magnifier) 与智能排版优化',
      'ImageDecoder 现代化图像与动图高效解码',
    ],
  ),
  // 左侧列第 3 项：Media
  AndroidFeatureSection(
    title: 'Media',
    titleZh: '多媒体技术',
    columnIndex: 0,
    items: [
      'HDR VP9 video',
      'HEIF image compression',
      'Improved media APIs',
    ],
    itemsZh: [
      'HDR VP9 Profile 2 视频解码播放支持',
      'HEIF 高效图像压缩格式原生支持',
      '音频会话路由与音量控制 API 增强',
    ],
  ),
  // 右侧列第 1 项：Security and privacy
  AndroidFeatureSection(
    title: 'Security and privacy',
    titleZh: '安全与隐私保护',
    columnIndex: 1,
    items: [
      'Android Protected Confirmation',
      'Biometric authentication dialogs',
      'Hardware security module',
      'Secure key import',
      'Client-side encryption backups',
    ],
    itemsZh: [
      '安全确认交互 (Android Protected Confirmation)',
      '统一生物识别系统认证对话框 (BiometricPrompt)',
      'StrongBox 硬件级专用安全芯片模块',
      '安全密钥隔离导入机制',
      '客户端私钥端到端加密备份机制',
    ],
  ),
  // 右侧列第 2 项：Accessibility
  AndroidFeatureSection(
    title: 'Accessibility',
    titleZh: '无障碍辅助功能',
    columnIndex: 1,
    items: [
      'Navigation semantics',
      'Convenience actions',
      'Magnifier',
    ],
    itemsZh: [
      '无障碍导航语义属性规范支持',
      '无障碍快捷辅助全局操作手势',
      '系统级放大镜视图组件 (Magnifier)',
    ],
  ),
];
