import 'android_version_distribution_data.dart';

/// Android 3.0 (Honeycomb) 官方特性列表（中英双语对照）
/// 专为平板大屏设计，引入 Fragment 与 ActionBar 划时代架构
const List<AndroidFeatureSection> kAndroid30Features = [
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'Fragment Architecture: Modular UI controllers introduced for multi-pane layouts across phones and tablets.',
      'ActionBar Navigation: Standardized application top app bar with actions, menus, and tabs.',
      'Property Animation Framework: ValueAnimator and ObjectAnimator introduced, replacing legacy View animations.',
      'Hardware-Accelerated 2D: Global 2D drawing pipeline accelerated via GPU (android:hardwareAccelerated).',
      'High-Performance Renderscript: Heterogeneous computing 3D and graphics framework for high computational tasks.',
    ],
    itemsZh: [
      'Fragment 碎片化架构诞生：引入模块化可复用 UI 控制器，奠定多窗格响应式大屏界面开发标准。',
      'ActionBar 顶部导航体系：系统统一规范标题栏、操作菜单与标签导航，彻底取代旧版菜单弹出机制。',
      '属性动画 (Property Animation) 框架：引入 ValueAnimator 与 ObjectAnimator，实现真实对象属性平滑插值动画。',
      '2D 图形全局硬件加速：支持在清单中开启 GPU 硬件加速渲染管线，大幅提升复杂绘制效率。',
      'RenderScript 高性能计算框架：针对大算力图像滤镜与图形处理提供异构跨平台并行运算。',
    ],
  ),
  AndroidFeatureSection(
    title: 'Tablet OS Experience',
    titleZh: '平板大屏专属体验',
    columnIndex: 1,
    items: [
      'Holographic dark UI theme for tablets',
      'System bar with soft navigation keys and notifications',
      'USB Host API and accessory connection support',
      'Redesigned multi-tasking recents list',
    ],
    itemsZh: [
      '全息科技风暗黑平板专属交互界面',
      '集成虚拟导航键与常驻通知状态的系统底栏',
      'USB Host API 原生外部外设直连支持',
      '全新横向可视化最近任务卡片列表',
    ],
  ),
];

/// Android 2.3 (Gingerbread) 官方特性列表（中英双语对照）
const List<AndroidFeatureSection> kAndroid23Features = [
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'StrictMode Introduced: Developer tool detecting accidental main-thread disk I/O and network operations causing ANRs.',
      'Concurrent Garbage Collector: Reduced Dalvik GC pauses, mitigating frame drops and UI stuttering.',
      'Multiple Cameras Support: Native API for front-facing selfie cameras and camera switching.',
      'Near Field Communication (NFC): Native NDEF tag reading and contactless communication API.',
      'Native Audio (OpenSL ES): Low-latency native audio API for gaming and professional audio applications.',
    ],
    itemsZh: [
      'StrictMode 严苛模式：在运行时监控主线程磁盘 I/O 与网络请求，帮助开发者彻底杜绝 ANR 无响应。',
      '并发垃圾回收器 (Concurrent GC)：大幅削减 Dalvik GC 造成的线程冻结停顿，画面顿卡显著减少。',
      '多摄像头原生 API：首次系统级支持前置摄像头与多摄像头动态切换。',
      '近场通信 (NFC) API：支持读取 NDEF 智能标签与双向近场数据交互。',
      'OpenSL ES 原生音频支持：针对大型游戏开发提供底层极低延迟音频混音与音效。',
    ],
  ),
  AndroidFeatureSection(
    title: 'Gaming & Performance',
    titleZh: '游戏开发与能效优化',
    columnIndex: 1,
    items: [
      'Native Activity (android.app.NativeActivity) for pure C/C++ games',
      'Sensors: Gyroscope, rotation vector, linear acceleration sensors',
      'Improved power management and aggressive background task audit',
      'DownloadManager system-wide background download service',
    ],
    itemsZh: [
      'NativeActivity 原生支持：允许纯 C/C++ NDK 编写大型游戏主入口',
      '传感器丰富化：新增陀螺仪、旋转矢量与线性加速度计支持',
      '精细化电池能耗分析与后台过载任务监管',
      'DownloadManager 系统级大文件后台下载服务',
    ],
  ),
];

/// Android 2.2 (Froyo) 官方特性列表（中英双语对照）
const List<AndroidFeatureSection> kAndroid22Features = [
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'Dalvik JIT (Just-In-Time) Compiler: 2x to 5x performance boost for CPU-bound computations.',
      'Install Apps to External Storage: android:installLocation manifest attribute enabling SD-card app installation.',
      'Cloud to Device Messaging (C2DM): Official push notification service predecessor to GCM and FCM.',
      'Enterprise Device Administration API: Security policies for remote wipe, screen lock, and PIN enforcements.',
    ],
    itemsZh: [
      'Dalvik JIT 即时编译器：CPU 密集型计算任务执行速度提升 2 到 5 倍。',
      '支持将应用安装至外部 SD 卡：在清单中声明 android:installLocation 缓解机身内部存储焦虑。',
      '云端消息推送服务原型 (C2DM)：Google 官方推送服务起点，开启非轮询下行通知时代。',
      '企业设备管理器 API：支持远程擦除、强制密码锁定与企业安全合规策略。',
    ],
  ),
  AndroidFeatureSection(
    title: 'Platform Capabilities',
    titleZh: '平台能力扩展',
    columnIndex: 1,
    items: [
      'Wi-Fi hotspot tethering functionality',
      'V8 JavaScript engine integrated into native browser',
      'High-resolution multi-screen density (xhdpi) preparation',
      'Camera and Camcorder quick-toggle controls',
    ],
    itemsZh: [
      '系统级便携式 Wi-Fi 热点网络共享支持',
      '原生浏览器集成 V8 JavaScript 高速引擎',
      '超高分辨率屏幕密度 (xhdpi) 适配体系前置铺垫',
      '相机与录像快捷操控界面与变焦优化',
    ],
  ),
];

/// Android 2.0 / 2.1 (Eclair) 官方特性列表（中英双语对照）
const List<AndroidFeatureSection> kAndroid20Features = [
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'AccountManager Framework: Centralized account synchronization and authentication system architecture.',
      'Multi-Touch Gestures: Native platform support for multi-touch pinch and gesture tracking.',
      'Live Wallpapers (WallpaperService): Interactive OpenGL and animated backgrounds on home screens.',
      'Bluetooth 2.1 & OPP/SPP: Native Object Push and Serial Port profile communication.',
    ],
    itemsZh: [
      'AccountManager 账户管理框架：系统级统一多账户凭据认证与后台自动同步体系。',
      '多点触控与手势识别：原生支持双指捏合缩放与多指并发触控交互。',
      '动态壁纸服务 (WallpaperService)：支持开发基于 OpenGL 渲染的高性能桌面互动动态壁纸。',
      '蓝牙 2.1 与 OPP/SPP 协议：支持免配对近场文件交换与串口设备通信。',
    ],
  ),
  AndroidFeatureSection(
    title: 'Hardware & Browser',
    titleZh: '硬件支持与浏览器',
    columnIndex: 1,
    items: [
      'Camera flash, digital zoom, and color effect parameters',
      'HTML5 audio and video tag support in browser',
      'Revamped contact search and Quick Contact badges',
    ],
    itemsZh: [
      '相机闪光灯控制、数码变焦与色彩特效参数 API',
      '系统内置浏览器支持 HTML5 音频与视频标签',
      '全新快速联系人徽章 (Quick Contact) 弹窗浮层',
    ],
  ),
];

/// Android 1.6 (Donut) 官方特性列表（中英双语对照）
const List<AndroidFeatureSection> kAndroid16DonutFeatures = [
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'Multi-Density Screen Architecture (dp/dpi): Landmark display adaptation system introducing ldpi, mdpi, and hdpi.',
      'Text-to-Speech (TTS) Engine: Multilingual speech synthesis native framework (android.speech.tts).',
      'Quick Search Box: Apps can register as searchable providers in the universal search widget.',
      'GestureBuilder & GestureOverlayView: Custom gesture recognition algorithms and touch training tools.',
    ],
    itemsZh: [
      '多屏幕密度体系 (dp/dpi)：里程碑式建立 ldpi、mdpi、hdpi 资源限定符与密度无关像素体系，确立跨机型适配基石。',
      '文本转语音 (TTS) 原生引擎：系统级多国语言语音合成接口 (android.speech.tts)。',
      '全局快速搜索框 (QSB)：第三方应用可注册 Searchable Provider 将私有数据接入桌面搜索。',
      '手势识别体系 (GestureBuilder)：提供触摸手势录制、特征提取与交互识别工具。',
    ],
  ),
  AndroidFeatureSection(
    title: 'Market & Connectivity',
    titleZh: '商店与网络',
    columnIndex: 1,
    items: [
      'Android Market user interface redesign',
      'CDMA/EVDO network architecture support',
      'Battery usage indicator and per-app consumption stats',
    ],
    itemsZh: [
      'Android Market 应用商店首度界面全面重构',
      '系统底层原生支持电信 CDMA/EVDO 网络通信',
      '电池电量消耗统计与单应用耗电占比追踪',
    ],
  ),
];

/// Android 1.5 (Cupcake) 官方特性列表（中英双语对照）
const List<AndroidFeatureSection> kAndroid15CupcakeFeatures = [
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'Input Method Framework (IMF): On-screen virtual keyboard architecture supporting third-party soft keyboards.',
      'AppWidgets: Interactive live micro-applications embedded directly on the user home screen.',
      'Live Video Recording & Playback: MPEG-4 and 3GP video capture capabilities for developers.',
      'Bluetooth A2DP & AVRCP: Wireless stereo audio streaming and playback control.',
    ],
    itemsZh: [
      '输入法框架 (IMF)：建立屏幕虚拟软键盘架构，开放第三方输入法开发通道。',
      '桌面小部件 (AppWidget)：首创在手机主屏幕桌面嵌入可交互式动态应用小部件。',
      '视频录制与回放能力：原生支持 MPEG-4 与 3GP 视频录制 API。',
      '蓝牙 A2DP 与 AVRCP：原生支持高品质立体声无线音频串流与播放控制。',
    ],
  ),
  AndroidFeatureSection(
    title: 'UI Animations & Media',
    titleZh: 'UI 动效与多媒体',
    columnIndex: 1,
    items: [
      'Custom window animations and transition effects',
      'Auto-rotation sensor integration',
      'Direct YouTube and Picasa media sharing Intents',
    ],
    itemsZh: [
      '自定义窗口转场动画与 Activity 切换特效',
      '基于重力感应器的屏幕自动横竖屏旋转',
      '系统级快速媒体分享 Intent 通道',
    ],
  ),
];

/// Android 1.0 / 1.1 (Base) 官方特性列表（中英双语对照）
const List<AndroidFeatureSection> kAndroid10BaseFeatures = [
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'Core Four Components: Activity, Service, BroadcastReceiver, and ContentProvider defined the Android paradigm.',
      'AndroidManifest.xml: Declarative application manifest architecture for components, permissions, and metadata.',
      'Intent Messaging Bus: Decoupled inter-component and inter-application asynchronous messaging mechanism.',
      'Dalvik Virtual Machine & APK: Custom register-based bytecode VM and packaged zip distribution architecture.',
    ],
    itemsZh: [
      '四大核心组件体系确立：Activity、Service、BroadcastReceiver、ContentProvider 奠定 Android 架构基石。',
      'AndroidManifest.xml 声明规范：确立组件声明、权限管控与元数据配置核心规范。',
      'Intent 消息总线：解耦的跨组件与跨进程松耦合通信机制。',
      'Dalvik 虚拟机与 APK 格式：专为移动端设计的寄存器字节码虚拟机与打包分发格式。',
    ],
  ),
  AndroidFeatureSection(
    title: 'Foundational Platform APIs',
    titleZh: '平台基石能力',
    columnIndex: 0,
    items: [
      'View hierarchy and basic widget toolkit (Button, TextView, ListView)',
      'SQLite database integration for local relational storage',
      'LocationManager (GPS and Cell-ID tower triangulation)',
      'Google Maps external library and basic web browser component',
    ],
    itemsZh: [
      'View 视图树与基础控件集 (Button, TextView, ListView 等)',
      '集成 SQLite 关系型轻量级本地数据库',
      'LocationManager 位置管理体系（GPS 与基站三角定位）',
      'Google Maps 扩展库支持与基础网页渲染控件',
    ],
  ),
];
