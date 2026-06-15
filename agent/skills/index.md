# Skill Index (AI 技能索引)

本索引用于管理 AdbManage 项目内的 AI 技能 (Skills)。所有的 AI 助手在处理本项目的开发和优化需求前，应根据本索引的指引，优先调取对应能力的技能文档。

## 命名与类别规则

- **adb-***：针对当前 AdbManage 桌面端项目技术栈专属，包含 Flutter Desktop, Riverpod, ADB shell 进程以及 scrcpy 投屏深度集成规范。
- **doc-***：产出交付类技能，可跨技术栈复用。

## 技能列表

### 1. 入口类技能 (Entry)

| Skill | 中文名 | 状态 | 用途 | 典型触发语 |
| --- | --- | --- | --- | --- |
| `adb-feature-orchestrator` | 功能开发总编排 | active | 需求总入口与代码修改总纲。包含每次修改代码的 5 大维度自查清单（投屏、国际化、明暗主题、性能、安全），编排开发规划、同质化检查与多窗口同步 | `我要开发个新功能`、`新增一个功能板块`、`重构xxx模块`、`修改代码` |

### 2. 能力与检查类技能 (Capabilities)

| Skill | 中文名 | 状态 | 用途 | 典型触发语 |
| --- | --- | --- | --- | --- |
| `adb-project-context` | 项目上下文索引 | active | 维护项目目录结构、技术栈、Isolate 限制、核心全局 Provider 列表及风险记录 | `项目结构是怎样的`、`有哪些核心Provider` |
| `adb-multiwindow-sync` | 多窗口同步梳理 | active | 分析跨 Isolate 状态同步流程，校验 Method Channel 通信逻辑与 SharedPreferences 读写安全性 | `同步语言状态`、`跨窗口传递参数`、`子窗口置顶逻辑` |
| `adb-process-management` | CLI 进程安全设计 | active | 审核后台 Process 启动、标准流监听、Timeout 限制与资源回收逻辑，规避僵尸进程 | `后台执行adb命令`、`Logcat实时输出`、`进程泄漏检查` |
| `adb-performance-review` | 桌面端性能审查 | active | 审查投屏帧率延迟、大文本终端渲染卡顿、CPU 占用及 Riverpod Provider 触发 rebuild 频率 | `投屏很卡`、`优化渲染性能`、`终端卡顿优化` |
| `adb-similarity-check` | 页面/组件同质化检查 | active | 检查是否存在重复的 CLI 工具封装、公共弹窗组件或重复的 settings 控制逻辑 | `有没有类似组件`、`提取公共Helper` |

### 3. 产出类技能 (Outputs)

| Skill | 中文名 | 状态 | 用途 | 典型触发语 |
| --- | --- | --- | --- | --- |
| `doc-requirement-spec` | 需求交接文档 | active | 生成给后续 AI 或开发者接手的技术实现与变更细节文档 | `生成交接文档`、`需求技术规格书` |
| `doc-test-impact-spec` | 测试与回归影响文档 | active | 生成改动影响范围、边缘测试用例、回归路径及 adb 模拟测试命令 | `生成测试影响范围`、`怎么验证这个修改` |
| `doc-git-commit` | Git 规范化提交 | active | 查看以往 git 消息风格并总结实际问题，规范化生成 commit message 提交代码 | `提交代码`、`git commit`、`帮我写commit message` |

## 推荐技能组合

### 新增 Tab 页面 / 独立子窗口
```text
adb-feature-orchestrator -> adb-project-context -> adb-multiwindow-sync -> adb-similarity-check -> doc-test-impact-spec
```

### 接入新的 ADB 命令或实时流（终端/日志）
```text
adb-feature-orchestrator -> adb-project-context -> adb-process-management -> adb-performance-review -> doc-test-impact-spec
```

### 优化或调试投屏/交互触控逻辑
```text
adb-feature-orchestrator -> adb-process-management -> adb-performance-review -> doc-test-impact-spec
```

## 核心代码修改自查维度 (Critical Code Change Checklist)
在修改或开发代码时，必须强制对照 `adb-feature-orchestrator` 中的以下五个核心维度进行评估：
1. **投屏功能 (Screen Mirroring)**：是否破坏投屏流畅度、手势映射、键盘输入、Isolate 通信或物理屏幕亮灭还原？
2. **中英文国际化 (Chinese-English Localization)**：严禁硬编码文案，所有可见文案必须录入 l10n，且同步主/子窗口的多语言状态。
3. **暗黑和白天模式 (Dark/Light Modes)**：UI 在明暗两套主题下配色必须自适应，且确保可读性，不得硬编码固定色值。
4. **性能 (Performance)**：避免高频/过度 UI rebuild (使用 select)，对大量日志或终端文本使用虚拟列表 + 节流防抖，避免僵尸进程。
5. **安全 (Security)**：防范 ADB 参数拼接注入，保证 MethodChannel 参数及 SharedPreferences 读写安全性。

## 新增 Skill 规则
新增技能文档前必须先确认：
1. 预估此逻辑或规范会在项目开发中被**重复调取 3 次以上**。
2. 现有技能列表（包含 Core Rules）无法清晰覆盖该场景。
3. 包含了需要长期沉淀的特定系统命令、复杂数据结构或第三方插件协议（例如 scrcpy 协议或 MethodChannel 协议）。

