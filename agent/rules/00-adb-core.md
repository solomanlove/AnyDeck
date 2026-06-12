---
description: AdbManage 核心架构与 Dart/Flutter 开发规范
alwaysApply: true
---

# 项目技术基线
- **开发语言与 SDK**：Dart SDK `^3.11.4` + Flutter SDK。
- **状态管理**：`flutter_riverpod: ^3.3.1` (Notifier/NotifierProvider/FutureProvider)。
- **路由管理**：`go_router: ^17.2.3`。
- **窗口与系统栏**：
  - `window_manager: ^0.4.3` 用于无边框/隐藏原生标题栏、窗口拖拽、最小化到系统托盘。
  - `desktop_multi_window: ^0.2.0` 用于实现多窗口独立运行（如投屏子窗口、模拟器详情窗口）。
  - `tray_manager: ^0.5.2` 用于 macOS/Windows 的系统托盘控制。

# 架构分层设计
1. **Core 基础设施层** (`lib/core/`)
   - 底层 ADB 服务包装 (`lib/core/adb/`)：提供设备发现、Shell 执行、截图、录制等无状态薄封装。
   - 进程管理 (`lib/core/process/`)：处理命令行执行、工具路径解析、文件系统操作。
   - 设备投屏 (`lib/core/scrcpy/`)：连接投屏服务，接收帧数据、编排触控/按键映射。
   - 全局 Provider (`lib/core/providers/`)：提供设备列表流、全局设置等状态订阅。
2. **Features 业务模块层** (`lib/features/`)
   - 采用 Feature 分块设计。如：`lib/features/dashboard/`。
   - 表现层设计位于 `presentation/` 目录中，按功能或 Tab 进一步拆分子目录（如 `apps`, `control`, `devices`, `layout`, `logcat`, `screenshot`, `terminal` 等）。
3. **App 框架层** (`lib/app/`)
   - 包含路由 `router/`、多语言 `l10n/`、主题 `theme/`、设置 `settings/` 及窗口入口定义 `window/`。

# 代码编写约束 (CRITICAL)
- **局部修改与风格一致**：每次改动代码时，**绝对不能改动任何与当前修改目标无关的代码**。必须保持原有文件中的其他代码、注释、排版、格式和缩进风格完全一致。禁止任何与当前任务无关的重构、格式化或风格替换，以防污染 Git Diff 历史。
- **精简提交文件**：在代码格式化后，提交前必须使用 `git checkout` / `git restore` 撤销所有仅有格式化、空格、换行变动的无关文件，保持 `git status` 和 `git diff` 干净，只保留与当前功能直接相关的文件变动，确保 Commit 纯净。
- **需求与知识库沉淀**：每次新增的需求，开发完成后均必须将其技术设计、关键实现与命令机制以知识库文档（Knowledge，位于 `agent/knowledge/`）的形式沉淀，并更新知识库索引（`agent/knowledge/index.md`），以保证知识库的持续更新。
- **文件行数限制**：新增或重构后的 Dart 文件**禁止超过 500 行**。对于超过 500 行的 UI 文件，必须按样式、功能或自定义 Widget 拆分至独立文件，或者将逻辑剥离到 Riverpod Notifier 中。
- **工具类与拆分优先**：发现重复 UI、重复 Result 处理、重复路径/格式化/解析逻辑时，先查已有公共 helper、service、extension 或 widget；没有合适入口时，再新增职责单一的小工具类或拆分文件，禁止在多个 Tab 内复制粘贴同一段实现。
- **术语与双语支持**：
  - 代码注释和文档必须默认使用**中文**。
  - API、CLI 参数、类名、协议方法等术语保留 **English** 原文（例如 ViewModel, Provider, Hook, CLI, Channel）。
- **组件复用**：修改 UI 时，优先收口公共组件（如自定义的 LoadingIndicator, CustomButton 等）或共享 Helper，避免在多处重复手写相似的 UI 组件。
- **不可变 Widget 优先**：Flutter UI 默认优先使用 `const StatelessWidget`、纯函数式 helper 或 immutable 数据模型。只有确实需要 `TextEditingController`、`FocusNode`、`AnimationController`、订阅释放、滚动控制器等生命周期资源时，才使用 `StatefulWidget` / `ConsumerStatefulWidget`。
- **注释边界**：新增工具类、跨文件 helper、复杂异步流程必须加简短中文注释说明职责和边界；简单属性赋值、显而易见的 UI 拼装不写噪音注释。
- **防重复/安全调用**：
  - 涉及到 ADB 命令、脚本执行或投屏切换时，必须设置合理的 Timeout（一般为 15 秒）。
  - UI 操作应加入 Loading 状态或对按钮进行防重复点击处理。
