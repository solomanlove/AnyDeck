import 'android_version_distribution_data.dart';

/// Android 15 (V) 官方特性列表（中英双语对照）
/// 涵盖 Camera and media, Connectivity, Developer productivity and tools,
/// Graphics, Large screens, Performance and battery, Privacy, Security, User experience
const List<AndroidFeatureSection> kAndroid15Features = [
  // 开发影响与适配要求（置顶展示）
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    items: [
      'Edge-to-Edge by default: Apps targeting Android 15 (API 35) are forced into edge-to-edge mode. Status and navigation bars are transparent; WindowInsets handling is mandatory.',
      '16 KB Page Sizes support: Android 15 supports 16 KB memory pages. Native C/C++ SO shared libraries must be built with 16 KB ELF alignment (-Wl,-z,max-page-size=16384) to prevent crashes on 16KB devices.',
      'Foreground Service Restrictions: Strict timeout limits (6 hours) for dataSync and mediaProcessing foreground service types.',
      'Private Space Isolation: Apps and sensitive data can be sandboxed into isolated user profiles.',
      'Screen Recording Detection: New APIs notify apps when their window is being recorded or mirrored.',
    ],
    itemsZh: [
      'EdgeToEdge 全面强制适配：targetSdkVersion 35 默认强制开启边到边沉浸式，系统状态栏与导航栏完全透明，必须显式监听并处理 WindowInsets 边衬区以防界面被遮挡。',
      '新增 16KB 页面内存对齐要求：引入 16 KB Page Sizes 内存分页支持。包含原生 C/C++ SO 动态库的应用必须以 16 KB ELF 对齐重新构建编译 (-Wl,-z,max-page-size=16384)，否则在 16KB 设备上运行直接崩溃。',
      '前台服务类型与超时限制：dataSync（数据同步）和 mediaProcessing 类型前台服务最长限制运行 6 小时，超时将触发系统中断；强制约束前台服务规范。',
      '私密空间 (Private Space) 沙盒隔离：支持将应用独立移入私密空间，通知、快捷方式与应用数据全方位隔离。',
      '屏幕录制状态感知：新增系统级屏幕录制感知回调 API，敏感界面可检测并实施安全防录屏防截屏防护。',
    ],
  ),
  // 左侧列第 1 项：Camera and media
  AndroidFeatureSection(
    title: 'Camera and media',
    titleZh: '相机与多媒体',
    items: [
      'Low Light Boost',
      'In-app Camera Controls',
      'HDR headroom control',
      'Loudness control',
      'Virtual MIDI 2.0 Devices',
      'More efficient AV1 software decoding',
    ],
    itemsZh: [
      '弱光增强 (Low Light Boost)',
      '应用内高级相机控制',
      'HDR 余量控制 (HDR headroom control)',
      '响度控制标准 (Loudness control)',
      '虚拟 MIDI 2.0 设备支持',
      '更高效的 AV1 软件解码',
    ],
  ),
  // 左侧列第 2 项：Connectivity
  AndroidFeatureSection(
    title: 'Connectivity',
    titleZh: '连接性与通信',
    items: [
      'Satellite support',
      'Smoother NFC experiences',
      'Wallet role',
    ],
    itemsZh: [
      '卫星通信支持',
      '更流畅可靠的 NFC 交互体验',
      '电子钱包角色 (Wallet role) 规范',
    ],
  ),
  // 左侧列第 3 项：Developer productivity and tools
  AndroidFeatureSection(
    title: 'Developer productivity and tools',
    titleZh: '开发者生产力与工具',
    items: [
      'OpenJDK 17 updates',
      'PDF improvements',
      'Automatic language switching refinements',
      'Improved OpenType Variable Font API',
      'Granular line break controls',
      'App archiving',
    ],
    itemsZh: [
      'OpenJDK 17 核心库升级',
      'PDF 渲染与查看能力增强',
      '自动语言切换机制优化',
      '改进的 OpenType 可变字体 API',
      '细粒度文字换行控制',
      '应用归档 (App archiving) 系统级支持',
    ],
  ),
  // 左侧列第 4 项：Graphics
  AndroidFeatureSection(
    title: 'Graphics',
    titleZh: '图形技术',
    items: [
      'Modernizing Android\'s GPU access',
      'Improvements for Canvas',
    ],
    itemsZh: [
      '现代化 Android GPU 访问架构',
      'Canvas 绘图性能与能力优化',
    ],
  ),
  // 左侧列第 5 项：Large screens and form factors
  AndroidFeatureSection(
    title: 'Large screens and form factors',
    titleZh: '大屏与多设备形态',
    items: [
      'Improved large screen multitasking',
      'Cover screen support',
    ],
    itemsZh: [
      '大屏多任务处理体验优化',
      '折叠屏外屏 (Cover screen) 深度适配支持',
    ],
  ),
  // 右侧列第 1 项：Performance and battery
  AndroidFeatureSection(
    title: 'Performance and battery',
    titleZh: '性能与电池能效',
    items: [
      'ApplicationStartInfo API',
      'Detailed app size information',
      'App-managed profiling',
      'SQLite database improvements',
      'Android Dynamic Performance Framework updates',
    ],
    itemsZh: [
      'ApplicationStartInfo 启动信息 API',
      '更详尽精确的应用体积信息',
      '应用自主性能剖析 (App-managed profiling)',
      'SQLite 数据库性能深度优化',
      'Android 动态性能框架 (ADPF) 更新',
    ],
  ),
  // 右侧列第 2 项：Privacy
  AndroidFeatureSection(
    title: 'Privacy',
    titleZh: '隐私保护',
    items: [
      'Screen recording detection',
      'Expanded IntentFilter capabilities',
      'Private space',
      'Query most-recent user selection for Selected Photos Access',
      'Privacy Sandbox on Android',
      'Health Connect',
      'Partial screen sharing',
    ],
    itemsZh: [
      '屏幕录制状态感知与检测',
      'IntentFilter 匹配能力扩展',
      '私密空间 (Private space)',
      '查询选定照片访问权限的最新用户选择',
      'Android 隐私沙盒 (Privacy Sandbox)',
      '健康数据连接 (Health Connect)',
      '部分屏幕共享保护机制',
    ],
  ),
  // 右侧列第 3 项：Security
  AndroidFeatureSection(
    title: 'Security',
    titleZh: '系统安全',
    items: [
      'Integrate Credential Manager with autofill',
      'Integrate single tap sign-up and sign-in with biometric prompts',
      'Key management for end-to-end encryption',
      'Permission checks on content URIs',
    ],
    itemsZh: [
      '凭据管理器与自动填充深度集成',
      '生物识别一键注册与登录集成',
      '端到端加密密钥管理机制',
      'Content URI 权限安全检查加固',
    ],
  ),
  // 右侧列第 4 项：User experience and system UI
  AndroidFeatureSection(
    title: 'User experience and system UI',
    titleZh: '用户体验与系统界面',
    items: [
      'Richer widget previews with Generated Previews API',
      'Picture-in-picture improvements',
      'Improved Do Not Disturb rules',
      'Set VibrationEffect for notification channels',
      'Media projection status bar chip and auto stop',
    ],
    itemsZh: [
      '基于生成式预览 API 的丰富小部件预览',
      '画中画 (PiP) 模式体验优化',
      '更灵活完善的勿扰模式规则',
      '为通知渠道配置 VibrationEffect 振动特效',
      '媒体投影状态栏药丸指示与自动停止',
    ],
  ),
];

/// Android 16 (B) 官方特性列表（中英双语对照）
const List<AndroidFeatureSection> kAndroid16Features = [
  // 开发影响与适配要求（置顶展示）
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    items: [
      'Predictive Back Default Migration: Predictive back gestures are mandatory by default for apps targeting Android 16+; legacy opt-out is deprecated.',
      'Edge-to-Edge Opt-out Removed: Legacy opt-out attributes for edge-to-edge system bars are completely removed for targeting 16+.',
      'Large Screen Adaptive Layouts: System defaults to ignoring portrait-only locks and fixed aspect ratios on tablets and foldables for targeting 16+.',
      'Health Connect Permission Transition: Mandatory migration to granular android.permissions.health permissions for health data access.',
      'Safer Intent Resolution: Stricter component resolution rules to mitigate Intent redirection and spoofing vulnerabilities.',
      'MediaStore Version Lockdown: MediaStore locks down legacy storage access paths for apps targeting 16+.',
    ],
    itemsZh: [
      '预测性返回默认强制迁移：针对 Android 16+ 应用默认强制启用预测性返回手势，退出选项已弃用，需完整接入 BackHandler/OnBackPressedCallback。',
      '边到边沉浸式移除退出开关：彻底移除旧版边缘到边缘的 opt-out 退出属性，应用界面必须全面自适应透明状态栏与导航栏。',
      '大屏设备忽略屏幕方向限制：针对 16+ 应用在大屏与折叠屏设备上，系统默认忽略 portrait 强制竖屏锁定及固定宽高比，必须适配响应式自适应布局。',
      'Health Connect 细粒度权限迁移：必须迁移至全新的细粒度健康与运动权限体系 (android.permissions.health)。',
      '更安全的 Intent 解析机制：针对 16+ 强化显式与隐式 Intent 组件匹配机制，严密防御重定向与特权提升攻击。',
      'MediaStore 隔离保护加固：系统对多媒体存储访问施加更严密的版本隔离与权限校验。',
    ],
  ),
  AndroidFeatureSection(
    title: 'User Experience and System UI',
    titleZh: '用户体验与系统界面',
    items: [
      'Progress-centric notifications',
      'Richer haptics APIs',
      'Predictive back updates and default migration/opt-out requirement (targeting 16+)',
      'Automatic themed app icons',
      'Edge to edge opt-out removed (targeting 16+)',
      'Deprecating disruptive accessibility announcements',
      'Content handling for live wallpapers',
    ],
    itemsZh: [
      '聚焦进度的通知体验优化',
      '更丰富的触觉反馈 (Haptics) API',
      '预测性返回手势更新与默认迁移要求（针对 16+）',
      '自动适配单色主题应用图标',
      '移除边缘到边缘沉浸式退出选项（针对 16+）',
      '废弃容易造成干扰的无障碍朗读提示',
      '动态壁纸内容处理机制优化',
    ],
  ),
  AndroidFeatureSection(
    title: 'Graphics',
    titleZh: '图形与视觉特效',
    items: [
      'Custom graphical effects with AGSL (RuntimeColorFilter, RuntimeXfermode)',
    ],
    itemsZh: [
      '基于 AGSL 的自定义图形特效（RuntimeColorFilter, RuntimeXfermode）',
    ],
  ),
  AndroidFeatureSection(
    title: 'Internationalization',
    titleZh: '国际化与多语言',
    items: [
      'Vertical text rendering support',
      'Measurement system customization in regional preferences',
    ],
    itemsZh: [
      '竖排文本渲染能力支持',
      '区域偏好设置中的度量系统自定义',
    ],
  ),
  AndroidFeatureSection(
    title: 'Device Form Factors',
    titleZh: '多设备形态与大屏适配',
    items: [
      'Standardized picture and audio quality framework for TVs (MediaQuality package)',
      'Virtual device owner overrides',
      'Adaptive layouts (platform ignores screen orientation/aspect ratio restrictions for targeting 16+)',
    ],
    itemsZh: [
      '标准化电视画质与音质框架（MediaQuality 模块）',
      '虚拟设备所有者权限重写支持',
      '自适应布局支持（针对 16+ 平台忽略屏幕方向与宽高比限制）',
    ],
  ),
  AndroidFeatureSection(
    title: 'Health and Fitness',
    titleZh: '健康与运动 (Health Connect)',
    items: [
      'Transition to granular health and fitness permissions (`android.permissions.health` for Health Connect) (targeting 16+)',
    ],
    itemsZh: [
      '细粒度健康与运动权限迁移（针对 16+ 引入 `android.permissions.health`）',
    ],
  ),
  AndroidFeatureSection(
    title: 'Security and Privacy',
    titleZh: '安全与隐私保护',
    items: [
      'Improved security against Intent redirection attacks',
      'Key sharing API for Android Keystore',
      'Privacy Sandbox on Android updates',
      'MediaStore version lockdown (targeting 16+)',
      'Safer Intent resolution mechanism (targeting 16+)',
      'GPU syscall filtering (targeting 16+)',
    ],
    itemsZh: [
      '针对 Intent 重定向攻击的安全防御增强',
      'Android Keystore 密钥共享 API',
      'Android 隐私沙盒 (Privacy Sandbox) 架构升级',
      'MediaStore 版本隔离保护（针对 16+）',
      '更安全的 Intent 解析机制（针对 16+）',
      'GPU 系统调用 (syscall) 安全过滤',
    ],
  ),
  AndroidFeatureSection(
    title: 'Camera and Media',
    titleZh: '相机与多媒体',
    items: [
      'UltraHDR image enhancements (HEIC)',
      'Precise color temperature and tint adjustments',
      'Hybrid auto-exposure modes',
      'Motion photo capture Intent actions',
      'Camera night mode scene detection (EXTENSION_NIGHT_MODE_INDICATOR)',
      'Photo picker improvements (embeddable, cloud search)',
    ],
    itemsZh: [
      'UltraHDR 图像画质增强支持 (HEIC 格式)',
      '更精确的色彩与色温调节',
      '混合自动曝光 (Hybrid Auto-Exposure) 模式',
      '动态照片 (Motion Photo) 捕获 Intent 接口',
      '相机夜景模式场景检测指示器',
      '照片选择器体验升级（支持内嵌与云端搜索）',
    ],
  ),
  AndroidFeatureSection(
    title: 'Core Functionality',
    titleZh: '核心系统与性能',
    items: [
      'ART internal changes and performance updates',
    ],
    itemsZh: [
      'ART 虚拟机内部架构优化与执行性能提升',
    ],
  ),
];
