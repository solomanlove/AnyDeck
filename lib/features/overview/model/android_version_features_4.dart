import 'android_version_distribution_data.dart';

/// Android 4.4 (KitKat) 官方特性列表（中英双语对照）
/// 涵盖对开发的影响、存储、系统界面、网络与多媒体等
const List<AndroidFeatureSection> kAndroid44Features = [
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'Storage Access Framework (SAF): Introduced standard document picker; direct file system path assumptions began deprecation.',
      'Translucent System Bars & Immersive Mode: Apps can draw behind status and navigation bars; SYSTEM_UI_FLAG_IMMERSIVE enables true fullscreen.',
      'Chromium-based WebView: Default WebView migrated to Chromium engine; stricter HTML5, modern CSS, and V8 JS parsing applied.',
      'Project Svelte 512MB RAM optimization: Apps must optimize memory allocations (Memory Leaks, Bitmap configurations) for low-RAM devices.',
      'Host Card Emulation (HCE): Secure contactless payments and NFC transactions enabled without secure SIM elements.',
    ],
    itemsZh: [
      '存储访问框架 (SAF)：引入全新文档提供者与选择器，直接访问文件物理路径的做法开始被规范化收口。',
      '透明系统栏与沉浸模式 (Immersive Mode)：支持将界面延伸至状态栏与导航栏后方，全屏游戏与多媒体需适配系统栏手势唤出。',
      '基于 Chromium 的全新 WebView：内核彻底重构，遵循严格现代 Web 标准与更强 JavaScript 引擎，部分非标准 Web 页面需兼容修复。',
      'Project Svelte 瘦身计划：系统可在 512MB 内存设备运行，要求开发者严格管控 Bitmap 内存开销防范 OOM。',
      'NFC 主机卡模拟 (HCE)：无需依赖运营商 SIM 卡安全元即可实现手机移动支付与门禁模拟开发。',
    ],
  ),
  AndroidFeatureSection(
    title: 'System & Multimedia Features',
    titleZh: '系统与多媒体特性',
    columnIndex: 1,
    items: [
      'Screen recording utility via ADB',
      'Native IR (Infrared) transmitter API',
      'Step detector and step counter composite sensors',
      'Experimental ART runtime preview in Developer Options',
    ],
    itemsZh: [
      '通过 ADB 命令行原生录制屏幕视频功能',
      '原生红外发射器 (Consumer IR) 控制 API',
      '计步器与步数检测复合硬件传感器 API',
      '开发者选项中首次引入实验性 ART 运行时预览',
    ],
  ),
];

/// Android 4.3 (Jelly Bean) 官方特性列表（中英双语对照）
const List<AndroidFeatureSection> kAndroid43Features = [
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'Bluetooth Low Energy (BLE / Bluetooth Smart): Central role native API enabling smartwatch and IoT accessories communication.',
      'OpenGL ES 3.0: Next-generation mobile 3D graphics pipeline with advanced texturing and shaders.',
      'Restricted Profiles: Multi-user environment controls for tablets restricting app availability and in-app purchases.',
      'NotificationListenerService: Apps can read and interact with system-wide notifications with explicit user permission.',
    ],
    itemsZh: [
      '低功耗蓝牙 (BLE) 原生支持：提供中心设备角色 API，开启可穿戴手环、手表及智能硬件通信新时代。',
      'OpenGL ES 3.0 支持：引入下一代移动端 3D 渲染管线、高级纹理压缩与着色器加速。',
      '受限个人资料 (Restricted Profiles)：平板多用户模式下细粒度限制特定应用的启动与应用内支付。',
      '通知侦听服务 (NotificationListenerService)：允许在获得用户授权后读取与交互全局通知信息。',
    ],
  ),
  AndroidFeatureSection(
    title: 'Media & Performance',
    titleZh: '多媒体与性能优化',
    columnIndex: 1,
    items: [
      'Modular DRM framework with MediaCrypto API',
      'UI profiling tool: Profile GPU rendering overlay',
      'Hardware-accelerated 2D rendering optimizations',
    ],
    itemsZh: [
      '模块化 DRM 数字版权保护框架与 MediaCrypto API',
      'UI 性能分析工具：支持在屏幕上实时叠加 GPU 呈现模式条形图',
      '2D 图形硬件加速管线持续优化与绘制缓存加速',
    ],
  ),
];

/// Android 4.2 (Jelly Bean) 官方特性列表（中英双语对照）
const List<AndroidFeatureSection> kAndroid42Features = [
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'RTL (Right-to-Left) Native Mirroring: Complete bidirectional text and layout mirroring for Arabic and Hebrew languages.',
      'Lock Screen Widgets: Developers can design AppWidgetProvider layouts tailored for device lock screens.',
      'Miracast Wireless Display: Native wireless screen sharing API over Wi-Fi Direct.',
      'Multi-user Support for Tablets: Multiple user profiles with isolated sandbox storage on shared tablet hardware.',
    ],
    itemsZh: [
      '全面支持 RTL 镜像布局：阿拉伯语与希伯来语等多语言自动镜像翻转排版，需使用 start/end 替代 left/right。',
      '锁屏微件 (Lock Screen Widgets)：允许开发者定制可在手机锁屏界面常驻展示的 AppWidget。',
      'Miracast 无线投屏：基于 Wi-Fi Direct 的无线屏幕镜像与独立次级屏幕渲染 API。',
      '平板多用户架构：单台平板支持多独立账户沙盒存储隔离与独立应用配置。',
    ],
  ),
  AndroidFeatureSection(
    title: 'Camera & Input',
    titleZh: '相机与输入交互',
    columnIndex: 1,
    items: [
      'Photo Sphere 360-degree panorama capture',
      'Gesture Typing keyboard with dynamic suggestion engine',
      'Daydream interactive screen saver mode',
    ],
    itemsZh: [
      'Photo Sphere 360 度全景球形照片拍摄',
      '滑行手势输入法 (Gesture Typing) 与动态词库联想',
      'Daydream 互动屏保充电展示模式',
    ],
  ),
];

/// Android 4.1 (Jelly Bean) 官方特性列表（中英双语对照）
const List<AndroidFeatureSection> kAndroid41Features = [
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'Project Butter (黄油计划): VSYNC synchronization, triple buffering, and touch response acceleration locking UI to 60fps.',
      'Rich Expandable Notifications: BigPictureStyle, BigTextStyle, and InboxStyle allowing custom actions without opening app.',
      'READ_EXTERNAL_STORAGE Permission: System begins strictly checking external storage read permissions.',
      'App Security: App encryption at install time and Smart App Updates via delta diff packages.',
    ],
    itemsZh: [
      'Project Butter (黄油计划)：引入垂直同步 (VSYNC)、三重缓冲与触摸事件优先响应，彻底解决卡顿，锁定 60fps 丝滑流畅度。',
      '富通知与可折叠大视图：支持大图、长文本、收件箱样式及直接在通知栏触发自定义 Action，无需拉起应用。',
      'READ_EXTERNAL_STORAGE 权限引入：系统开始针对外部共享存储读取操作进行独立权限校验。',
      '应用安装加密与增量更新：Google Play 开启 APK 增量差分更新，大幅降低用户升级流量消耗。',
    ],
  ),
  AndroidFeatureSection(
    title: 'Accessibility & Audio',
    titleZh: '无障碍与音频技术',
    columnIndex: 1,
    items: [
      'Gesture navigation and spoken feedback in TalkBack',
      'Low-latency audio playback and recording pipeline',
      'Bi-directional text and international font rendering enhancements',
    ],
    itemsZh: [
      'TalkBack 手势导航与屏幕语音朗读体系成熟化',
      '音频底层降低输出延迟，增强专业级音频录音与回放',
      '多国语言复杂文本与双向文字排版能力加固',
    ],
  ),
];

/// Android 4.0 (Ice Cream Sandwich) 官方特性列表（中英双语对照）
const List<AndroidFeatureSection> kAndroid40Features = [
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'Holo Design System: Unified dark/light modern themes bridging phone and tablet UX; deprecation of legacy pre-ICS styling.',
      'Virtual System Navigation Bar: On-screen Back/Home/Recents keys replaced hardware buttons; layouts must adapt to dynamic screen height.',
      'Unified Network Data Usage API: System tracks app traffic quotas and background data limits; apps should honor data saver flags.',
      'Social Provider and Profile API: Unified contacts directory integrating high-resolution photos and social status streams.',
    ],
    itemsZh: [
      'Holo 统一设计规范：终结手机与平板分支割裂，推行现代沉浸感 Holo 深浅主题体系，规范控件交互形态。',
      '虚拟导航栏全面取代实体按键：屏幕底部虚拟按键成为主流，应用界面需妥善适配动态屏幕可视安全区域。',
      '统一流量管理与限制 API：系统内置应用移动网络流量限额警告，应用需监听并响应后台数据受限状态。',
      '社交联系人与高清头像 API：整合高分辨率联系人头像、多社交平台状态流与个人 Profile 统一通讯录。',
    ],
  ),
  AndroidFeatureSection(
    title: 'UI Controls & Media',
    titleZh: 'UI 控件与多媒体',
    columnIndex: 1,
    items: [
      'GridLayout: High-performance 2D grid layout manager',
      'Face Unlock biometric authentication',
      'Wi-Fi Direct (P2P) high-speed local device connectivity',
      'Visual Voicemail and integrated spell checker framework',
    ],
    itemsZh: [
      'GridLayout 网格布局：高效扁平化二维网格布局容器，大幅减少嵌套层级',
      '人脸解锁 (Face Unlock) 生物识别前置初探',
      'Wi-Fi Direct (P2P) 点对点高速近场直连传输支持',
      '可视化语音信箱与系统级拼写检查服务框架',
    ],
  ),
];
