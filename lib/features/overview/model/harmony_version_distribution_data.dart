// HarmonyOS 鸿蒙系统版本与 API 分布数据模型。
// 数据来源：华为开发者联盟官方发布说明及官网存量 API 分布快照。

/// 鸿蒙版本分布明细项
class HarmonyDistributionItem {
  const HarmonyDistributionItem({
    required this.version,
    required this.api,
    required this.apiNum,
    required this.share,
    required this.cover,
    required this.release,
    required this.target,
    required this.compatible,
    required this.ide,
    required this.impacts,
    required this.core,
    required this.privacy,
    required this.link,
    this.muteFlag,
  });

  /// 版本号（如 7.0.0, 6.1.1）
  final String version;

  /// API 版本字符串（如 26.0.0, 24）
  final String api;

  /// API 主版本整数值（用于排序与比较）
  final int apiNum;

  /// 存量设备占比（如 18.98%, 75.02%）
  final String share;

  /// 累计设备覆盖率（如 18.98%, 94.00%）
  final String cover;

  /// 发布时间描述（如 2026-08-28 转正）
  final String release;

  /// 推荐 targetSdkVersion
  final String target;

  /// 推荐 compatibleSdkVersion
  final String compatible;

  /// 推荐 DevEco Studio 版本
  final String ide;

  /// 标签状态标识：'NEW'、'EOL' 或 null
  final String? muteFlag;

  /// 开发影响与行为变更要点
  final List<String> impacts;

  /// 平台核心基础设施能力
  final List<String> core;

  /// 安全与隐私保护特性
  final List<String> privacy;

  /// 华为开发者官方文档链接
  final String link;

  /// build-profile.json5 配置内容（可直接复制）
  String get buildProfileConfig {
    final comp = compatible.contains('（') ? compatible.split('（')[0].trim() : compatible;
    return '''// build-profile.json5
{
  "app": {
    "products": [{
      "name": "default",
      "targetSdkVersion": "$target",
      "compatibleSdkVersion": "$comp",
      "runtimeOS": "HarmonyOS"
    }]
  }
}''';
  }
}

/// 鸿蒙历史版本条目（1.0 ~ 5.0.x）
class HarmonyHistItem {
  const HarmonyHistItem({
    required this.version,
    required this.api,
    required this.releaseDate,
    required this.architecture,
    required this.shareStatus,
  });

  /// 版本号
  final String version;

  /// 对应 API 范围
  final String api;

  /// 发布日期与说明
  final String releaseDate;

  /// 技术底座与架构
  final String architecture;

  /// 存量占比或状态（如 已归零）
  final String shareStatus;
}

/// 鸿蒙版本分布数据仓库
class HarmonyVersionDistributionData {
  HarmonyVersionDistributionData._();

  /// 主力支持版本列表（7.0.0 降序到 5.0.5）
  static const List<HarmonyDistributionItem> items = [
    HarmonyDistributionItem(
      version: '7.0.0',
      api: '26.0.0',
      apiNum: 26,
      share: '18.98%',
      cover: '18.98%',
      release: '2026-08-28 转正',
      muteFlag: 'NEW',
      target: '7.0.0 (26)',
      compatible: '20 及以下（保守）/ 23（激进）',
      ide: 'DevEco Studio 26.0.0',
      impacts: [
        '底座：纯自研原生鸿蒙（5.0 起移除 AOSP），ArkTS + Stage 模型。',
        'Agent 智能方向：系统架构向 Agent 智能演进，智能体能力下沉至系统层，应用需按新框架调整 AI 能力接入方式。',
        'compatibleSdkVersion 建议保持 20 及以下：6.0 及以下版本仍有约 1.9% 存量设备，7.0 转正后建议按存量比例分阶段抬升。',
      ],
      core: [
        'DevEco Studio 26.0.0 Release（推荐使用）',
        '新增 Kit 维度能力扩展',
        'Stage 模型 Ability 生命周期增强',
      ],
      privacy: [
        '统一隐私治理框架',
        '系统级权限申请与最小化授权',
        '敏感数据访问审计留痕',
      ],
      link: 'https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-allversion',
    ),
    HarmonyDistributionItem(
      version: '6.1.1',
      api: '24',
      apiNum: 24,
      share: '75.02%',
      cover: '94.00%',
      release: '2026-05-26',
      target: '6.1.1 (24)',
      compatible: '20 及以下（保守）',
      ide: 'DevEco Studio 6.1.1',
      impacts: [
        '当前绝对主力版本，存量占比约 75%，是 compatibleSdkVersion 的主要基准。',
        'AbilityKit：增强 AbilityStage 上下文能力，支持动态加载资源。',
        'ArkUI：增强平行视界状态获取、自定义组件跨 Ability 迁移、动态布局容器，新增多个组件 C API。',
        'ArkTS：增强虚拟机维测能力，支持 taskpool 任务超时设置。',
        'ArkWeb：增强下载任务回调能力，新增 URL 白名单和安全控制接口。',
        'Camera Kit：新增延迟预览输出、影随人动能力，开放相机基础参数获取与设置。',
        'Audio Kit：新增 MIDI C API 支持外接设备。',
      ],
      core: [
        'DevEco Studio 6.1.1 Release',
        'ArkUI 动态布局容器与跨 Ability 组件迁移',
        'ArkWeb 安全控制接口',
      ],
      privacy: [
        'ArkWeb URL 白名单与安全控制',
        '动态加载资源的安全校验',
      ],
      link: 'https://developer.huawei.com/consumer/cn/doc/atomic-releases/atomic-releasenotes',
    ),
    HarmonyDistributionItem(
      version: '6.1.0',
      api: '23',
      apiNum: 23,
      share: '4.11%',
      cover: '98.11%',
      release: '2026-04-20',
      target: '6.1.0 (23)',
      compatible: '20 及以下（保守）',
      ide: 'DevEco Studio 6.1.0',
      impacts: [
        '与 6.1.1 合计覆盖约 98%，是兼容版本号选择的分水岭。',
        'HMAF 鸿蒙智能体框架：API 23 核心新增能力，将 AI 推理与智能体编排下沉至系统层。',
        '开发环境：ArkTS（Stage 模型），最低兼容 compileSdkVersion 23；适配设备覆盖手机、平板、PC(2in1)、智慧屏。',
      ],
      core: [
        'HMAF（HarmonyOS Model-Agent Framework）',
        '统一 IDE DevEco Studio 6.1.0',
        'Stage 模型支持 phone + 2in1 双端',
      ],
      privacy: [
        '智能体框架调用权限管控',
        '系统侧 AI 能力调用审计',
      ],
      link: 'https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-allversion',
    ),
    HarmonyDistributionItem(
      version: '6.0.2',
      api: '22',
      apiNum: 22,
      share: '1.27%',
      cover: '99.38%',
      release: '2026-01-21',
      target: '6.0.2 (22)',
      compatible: '—',
      ide: 'DevEco Studio 6.1.x（可向上兼容）',
      impacts: [
        '维护版本：以缺陷修复与安全补丁为主，不引入破坏性变更。',
        '兼容策略：仍处于百万级存量，暂不建议作为最低兼容版本放弃。',
      ],
      core: [
        '缺陷修复与安全补丁',
        '系统稳定性改进',
      ],
      privacy: [
        'Linux Kernel 等开源组件安全漏洞修复',
      ],
      link: 'https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-allversion',
    ),
    HarmonyDistributionItem(
      version: '6.0.1',
      api: '21',
      apiNum: 21,
      share: '0.33%',
      cover: '99.71%',
      release: '2025-11-20',
      target: '6.0.1 (21)',
      compatible: '—',
      ide: 'DevEco Studio 6.0.x',
      impacts: [
        '安全补丁版本：修复 Linux kernel 等开源组件安全漏洞。',
      ],
      core: [
        '安全与稳定性修复',
      ],
      privacy: [
        '开源组件漏洞修复',
      ],
      link: 'https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-allversion',
    ),
    HarmonyDistributionItem(
      version: '6.0.0',
      api: '20',
      apiNum: 20,
      share: '0.02%',
      cover: '99.73%',
      release: '2025-09-25',
      target: '6.0.0 (20)',
      compatible: '20（安全下限，覆盖 99.73%）',
      ide: 'DevEco Studio 6.0.0',
      impacts: [
        '官方推荐使用版本（开发套件口径）。',
        'ArkUI 组件能力与布局安全性增强。',
        '窗口能力与分布式数据管理增强。',
      ],
      core: [
        'ArkUI 组件能力与布局增强',
        '窗口能力增强',
        '分布式数据管理增强',
      ],
      privacy: [
        '布局安全性增强',
        '位置服务与输入法框架能力管控',
      ],
      link: 'https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-allversion',
    ),
    HarmonyDistributionItem(
      version: '5.1.1',
      api: '19',
      apiNum: 19,
      share: '0.07%',
      cover: '99.80%',
      release: '2025-06-30',
      muteFlag: 'EOL',
      target: '5.1.1 (19)',
      compatible: '不建议',
      ide: 'DevEco Studio 6.0+',
      impacts: [
        '5.X 时代版本号最高版本，占比仅 0.07%，官方建议升级直接至 6.0.0(20)。',
        '不再作为最低兼容版本候选。',
      ],
      core: ['5.1 系列收尾版本'],
      privacy: ['标准安全保护'],
      link: 'https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-allversion',
    ),
    HarmonyDistributionItem(
      version: '5.1.0',
      api: '18',
      apiNum: 18,
      share: '0.04%',
      cover: '99.84%',
      release: '2025-06-11',
      muteFlag: 'EOL',
      target: '5.1.0 (18)',
      compatible: '不建议',
      ide: 'DevEco Studio 6.0+',
      impacts: [
        '占比 0.04%，官方建议直接升级至 6.0.0(20)。',
      ],
      core: ['5.1 系列底座'],
      privacy: ['标准安全保护'],
      link: 'https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-allversion',
    ),
    HarmonyDistributionItem(
      version: '5.0.5',
      api: '17',
      apiNum: 17,
      share: '0.16%',
      cover: '100.00%',
      release: '2025-05-14',
      muteFlag: 'EOL',
      target: '5.0.5 (17)',
      compatible: '不建议',
      ide: 'DevEco Studio 6.0+',
      impacts: [
        '占比 0.16%，属于已被覆盖的长尾版本。',
      ],
      core: ['5.0 系列收尾'],
      privacy: ['标准安全保护'],
      link: 'https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-allversion',
    ),
  ];

  /// 历史版本（HarmonyOS 1.0 起）
  static const List<HarmonyHistItem> historyItems = [
    HarmonyHistItem(
      version: 'HarmonyOS 5.0.x',
      api: '12 ~ 16',
      releaseDate: '2024-08-04 发布 / 2025-03-20 正式推送',
      architecture: '纯自研原生鸿蒙起点（移除 AOSP）',
      shareStatus: '已归零',
    ),
    HarmonyHistItem(
      version: 'HarmonyOS 4.3',
      api: '9 ~ 11',
      releaseDate: '2024-11-26',
      architecture: 'AOSP 底座（Android 12）',
      shareStatus: '已归零',
    ),
    HarmonyHistItem(
      version: 'HarmonyOS 4.2',
      api: '9',
      releaseDate: '2024-04-11',
      architecture: 'AOSP 底座（Android 11/12）',
      shareStatus: '已归零',
    ),
    HarmonyHistItem(
      version: 'HarmonyOS 4.0',
      api: '9 ~ 11',
      releaseDate: '2023-08-04',
      architecture: 'AOSP 底座（Android 10/11/12）',
      shareStatus: '已归零',
    ),
    HarmonyHistItem(
      version: 'HarmonyOS 3.0',
      api: '8',
      releaseDate: '2021-10-22',
      architecture: 'AOSP 底座（Android 9/10/11/12）',
      shareStatus: '已归零',
    ),
    HarmonyHistItem(
      version: 'HarmonyOS 2.0',
      api: '6',
      releaseDate: '2020-09-10（2021-06-02 正式推送）',
      architecture: 'AOSP 底座（Android 9/10）',
      shareStatus: '已归零',
    ),
    HarmonyHistItem(
      version: 'HarmonyOS 1.0',
      api: '—',
      releaseDate: '2019-08-09',
      architecture: '仅用于智能屏',
      shareStatus: '已归零',
    ),
  ];
}
