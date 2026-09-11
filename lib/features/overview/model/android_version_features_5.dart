import 'android_version_distribution_data.dart';

/// Android 5.1 (Lollipop) 官方特性列表（中英双语对照）
/// 涵盖 Wireless & Connectivity, API Change
const List<AndroidFeatureSection> kAndroid51Features = [
  // 左侧列第 1 项：Wireless & Connectivity
  AndroidFeatureSection(
    title: 'Wireless & Connectivity',
    titleZh: '无线与数据连接',
    columnIndex: 0,
    items: [
      'Multiple SIM Card Support',
      'Carrier Provisioning',
    ],
    itemsZh: [
      '多 SIM 卡双卡双待系统级原生支持',
      '运营商服务自动预配与推送机制',
    ],
  ),
  // 左侧列第 2 项：API Change
  AndroidFeatureSection(
    title: 'API Change',
    titleZh: 'API 变更与废弃',
    columnIndex: 0,
    items: [
      'Deprecated HTTP Classes',
    ],
    itemsZh: [
      '正式废弃 Apache HTTP Client 客户端类库',
    ],
  ),
];

/// Android 5.0 (Lollipop) 官方特性列表（中英双语对照）
/// 涵盖 User Interface, Notifications, Graphics, Media, Storage, Wireless & Connectivity, Battery - Project Volta,
/// Android in the Workplace and in Education, Printing Framework, System, Testing & Accessibility, IME, Manifest Declarations
const List<AndroidFeatureSection> kAndroid50Features = [
  // 左侧列第 1 项：User Interface
  AndroidFeatureSection(
    title: 'User Interface',
    titleZh: '用户界面与交互',
    columnIndex: 0,
    items: [
      'Material design support',
      'Concurrent documents and activities in the recents screen',
      'WebView updates',
      'Screen capturing and sharing',
    ],
    itemsZh: [
      'Material Design 质感设计语言全面支持',
      '最近任务概览屏幕中多文档与 Activity 并发呈现',
      '独立通过 Google Play 更新的 Chromium WebView',
      '系统级屏幕录制与投影分享 API (MediaProjection)',
    ],
  ),
  // 左侧列第 2 项：Notifications
  AndroidFeatureSection(
    title: 'Notifications',
    titleZh: '通知系统',
    columnIndex: 0,
    items: [
      'Lock screen notifications',
      'Notifications metadata',
    ],
    itemsZh: [
      '锁屏界面悬浮与敏感内容隐私通知展示',
      '通知元数据与高优先级浮动通知 (Heads-up)',
    ],
  ),
  // 左侧列第 3 项：Graphics
  AndroidFeatureSection(
    title: 'Graphics',
    titleZh: '图形渲染技术',
    columnIndex: 0,
    items: [
      'Support for OpenGL ES 3.1',
      'Android Extension Pack',
    ],
    itemsZh: [
      'OpenGL ES 3.1 移动图形标准支持',
      'Android 扩展包 (AEP) 桌面级着色器特效',
    ],
  ),
  // 左侧列第 4 项：Media
  AndroidFeatureSection(
    title: 'Media',
    titleZh: '多媒体技术',
    columnIndex: 0,
    items: [
      'Camera API for advanced camera capabilities',
      'Audio playback',
      'Media playback control',
      'Media browsing',
    ],
    itemsZh: [
      'Camera2 API 支持 RAW 拍摄与手动曝光对焦控制',
      'AudioAttributes 多通道音频沉浸式播放',
      'MediaSession 统一多媒体播放控制器',
      'MediaBrowserService 跨进程多媒体库浏览服务',
    ],
  ),
  // 左侧列第 5 项：Storage
  AndroidFeatureSection(
    title: 'Storage',
    titleZh: '文件存储管理',
    columnIndex: 0,
    items: [
      'Directory selection',
    ],
    itemsZh: [
      '存储访问框架目录选择器 (OPEN_DOCUMENT_TREE)',
    ],
  ),
  // 左侧列第 6 项：Wireless & Connectivity
  AndroidFeatureSection(
    title: 'Wireless & Connectivity',
    titleZh: '无线与数据连接',
    columnIndex: 0,
    items: [
      'Multiple network connections',
      'Bluetooth Low Energy',
      'NFC enhancements',
    ],
    itemsZh: [
      '多网络并发连接评估与平滑切换',
      '低功耗蓝牙 (BLE) 外围设备模式支持',
      'NFC 触碰配对与数据交换体验增强',
    ],
  ),
  // 左侧列第 7 项：Battery - Project Volta
  AndroidFeatureSection(
    title: 'Battery - Project Volta',
    titleZh: '电池续航与 Volta 节能计划',
    columnIndex: 0,
    items: [
      'Scheduling jobs',
      'Developer tools for battery usage',
    ],
    itemsZh: [
      'JobScheduler 智能延迟能效后台任务调度器',
      'Battery Historian 电池耗电剖析工具支持',
    ],
  ),
  // 右侧列第 1 项：Android in the Workplace and in Education
  AndroidFeatureSection(
    title: 'Android in the Workplace and in Education',
    titleZh: '企业与教育场景应用',
    columnIndex: 1,
    items: [
      'Managed provisioning',
      'Device owner',
      'Screen pinning',
    ],
    itemsZh: [
      '托管工作资料 (Work Profile) 容器化部署',
      '设备所有者 (Device Owner) 集中管控模式',
      '屏幕固定 (Screen pinning) 展厅展位锁定模式',
    ],
  ),
  // 右侧列第 2 项：Printing Framework
  AndroidFeatureSection(
    title: 'Printing Framework',
    titleZh: '打印框架',
    columnIndex: 1,
    items: [
      'Render PDF as bitmap',
    ],
    itemsZh: [
      'PdfRenderer 将 PDF 页面高效渲染为位图',
    ],
  ),
  // 右侧列第 3 项：System
  AndroidFeatureSection(
    title: 'System',
    titleZh: '系统底层特性',
    columnIndex: 1,
    items: [
      'App usage statistics',
    ],
    itemsZh: [
      'UsageStatsManager 应用使用情况历史统计 API',
    ],
  ),
  // 右侧列第 4 项：Testing & Accessibility
  AndroidFeatureSection(
    title: 'Testing & Accessibility',
    titleZh: '测试与无障碍',
    columnIndex: 1,
    items: [
      'Testing and accessibility improvements',
    ],
    itemsZh: [
      '无障碍手势注入与 UI 自动化测试交互能力增强',
    ],
  ),
  // 右侧列第 5 项：IME
  AndroidFeatureSection(
    title: 'IME',
    titleZh: '输入法框架 (IME)',
    columnIndex: 1,
    items: [
      'Easier switching between input languages',
    ],
    itemsZh: [
      '输入法多语言之间便捷切换机制 (shouldOfferSwitchingToNextInputMethod)',
    ],
  ),
  // 右侧列第 6 项：Manifest Declarations
  AndroidFeatureSection(
    title: 'Manifest Declarations',
    titleZh: '应用清单声明',
    columnIndex: 1,
    items: [
      'Declarable required features',
      'User permissions',
    ],
    itemsZh: [
      'AndroidManifest 中支持声明更精确的硬件特性依赖',
      '安装时权限敏感分组展示与说明强化',
    ],
  ),
];
