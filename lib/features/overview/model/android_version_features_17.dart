import 'android_version_distribution_data.dart';

/// Android 17 (C) 官方特性列表（中英双语对照）
/// 涵盖对开发的影响、核心系统架构、AI系统级集成、安全隐私加固等
const List<AndroidFeatureSection> kAndroid17Features = [
  // 开发影响与适配要求（高优先级置顶展示）
  AndroidFeatureSection(
    title: 'Developer Impact & Migration',
    titleZh: '开发影响与适配要求',
    columnIndex: 0,
    items: [
      'Stricter Sandboxing for On-Device AI: Tensor processing and local AI model access require explicit fine-grained runtime permission grants.',
      'Aggressive Background Hibernation: System enforces stricter resource hibernation and throttling for long-unused applications.',
      'Accessibility Security Hardening: AccessibilityService overlays and automated credential interactions face enhanced sandboxing to prevent UI hijacking.',
      'Cross-Device Credential Roaming Gates: Mandatory cryptographic authorization required for seamless device-to-device credential sharing.',
      'Predictive Navigation Standardization: All transitions, dialogs, and nested navigations must comply with unified predictive gesture standards.',
    ],
    itemsZh: [
      '端侧 AI 与模型沙盒隔离：访问系统端侧模型引擎与神经处理单元引入细粒度权限限制，禁止非授权直接调用底座权重。',
      '后台休眠与资源调度激进收紧：长期闲置应用将被主动执行深度冻结，后台精准闹钟与广播唤醒受到更严苛配额限制。',
      '无障碍服务安全防劫持：全面收紧 AccessibilityService 覆盖层穿透与自动化操作凭据输入权限，防范恶意界面欺骗与劫持。',
      '跨设备凭据流转安全门禁：多设备互联协同流转用户凭据时强制要求双向密码学硬件认证。',
      '全场景预测性手势规范：弹窗、侧滑抽屉与嵌套导航必须全面遵循系统统一预测性手势过渡规范。',
    ],
  ),
  // 核心系统与性能
  AndroidFeatureSection(
    title: 'Core Platform & AI Infrastructure',
    titleZh: '平台核心与 AI 基础设施',
    columnIndex: 0,
    items: [
      'Next-generation ART Garbage Collection pipeline',
      'Unified on-device ML execution framework',
      'Dynamic power management for heterogeneous multi-cores',
    ],
    itemsZh: [
      '新一代 ART 虚拟机垃圾回收管线，进一步降低停顿耗时',
      '统一的端侧机器学习运行时加速框架',
      '异构多核处理器动态能效感知与调频调度优化',
    ],
  ),
  // 隐私与安全
  AndroidFeatureSection(
    title: 'Security and Privacy',
    titleZh: '安全与隐私保护',
    columnIndex: 1,
    items: [
      'Automated memory safety enforcements in native platform libraries',
      'Hardware-backed cryptographic keystore virtualization',
      'Stricter inter-process communication (IPC) payload auditing',
    ],
    itemsZh: [
      '系统原生底层库全面强化内存安全防护 (Memory Safety)',
      '硬件级 Keystore 虚拟化隔离与防篡改密钥保护',
      '跨进程通信 (IPC) 数据载荷运行时安全校验增强',
    ],
  ),
  // 用户体验与系统界面
  AndroidFeatureSection(
    title: 'User Experience & Connectivity',
    titleZh: '用户体验与互联互通',
    columnIndex: 1,
    items: [
      'Fluid predictive gesture transitions across all form factors',
      'Ultra-wideband (UWB) high-precision spatial positioning APIs',
      'Advanced multi-window spatial arrangement on foldable & desktop displays',
    ],
    itemsZh: [
      '全形态设备流畅无缝的预测性手势动画过渡',
      '超宽带 (UWB) 高精度空间相对测距与定位 API',
      '折叠屏与外接桌面多窗口自适应分屏空间布局增强',
    ],
  ),
];
