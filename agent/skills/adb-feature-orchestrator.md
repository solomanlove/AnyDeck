# Skill: adb-feature-orchestrator (功能开发总编排)

## 概述
本技能是开发 AdbManage 项目新需求或大型修改时的总协调中心。主要职责在于编排整体逻辑、确定修改范围、保障多窗口数据流和进程处理的正确性，并主导产出测试与交接文档。

## 工作流程

1. **第一步：环境与上下文审查**
   - 调取 `adb-project-context`，搞清楚新增功能涉及的模块位置（是 `lib/core` 还是 `lib/features/dashboard/presentation`）。
   - 确认是否有类似功能的 Tab、控制栏或 Provider。

2. **第二步：页面/窗口架构与通讯规划**
   - 评估新功能是否需要打开新的子窗口。
   - 如果需要，调取 `adb-multiwindow-sync`，规划参数传递格式以及跨 Isolate 状态同步机制。

3. **第三步：进程安全与性能风险评估**
   - 评估该功能是否需要运行后台 adb 命令行、接收 stdout/stderr 实时流。
   - 如果需要，调取 `adb-process-management`，规划超时中止、错误捕获与进程生命周期回收。
   - 评估投屏、截图或终端大数据渲染的性能风险，调取 `adb-performance-review`。

4. **第四步：同质化与冗余审查**
   - 调取 `adb-similarity-check`，核查当前项目是否已提供相似的 ADB 命令执行类（如 `AdbService` 已封装的常用方法），杜绝重复拼接 adb shell 命令。

5. **第五步：开发与本地校验**
   - 执行编码。注意控制单个文件行数在 **500 行以内**。
   - 运行静态检查及格式化命令：
     ```bash
     flutter analyze
     dart format .
     ```

6. **第六步：产出交付文档**
   - 调取 `doc-test-impact-spec` 产出 QA 验证计划。
   - 调取 `doc-requirement-spec` 产出交接文档。

## 每次修改代码的核心评估维度

在进行任何代码修改时，必须主动自查并确保满足以下五个维度的设计和规范要求：

### 1. 投屏功能 (Screen Mirroring)
- **物理与交互逻辑**：新改动是否影响投屏流畅度、鼠标与触摸手势的物理映射（缩放、偏移）、键盘输入重定向、或 `screenPowerOffProvider` 状态还原？
- **生命周期与回收**：投屏连接或断开时，相关 Isolate、Method Channel 及后台 `scrcpy` 进程是否能够安全回收，是否存在断开后重连失败或残留僵尸进程的问题？

### 2. 中英文国际化 (Chinese-English Localization)
- **杜绝硬编码**：禁止在 UI 中手写中文或英文文案。所有用户可见的文案必须定义在本地化资源类中，并通过 `AppLocalizations.of(context)` 获取。
- **多窗口同步**：新增或修改文案时，确保主窗口和子窗口的本地化文件都已同步补齐，且跨 Isolate 的语言广播（`'update_language'`）逻辑正常运行。

### 3. 暗黑和白天模式 (Dark/Light Modes)
- **颜色与主题自适应**：所有新增或修改的 UI 组件（包括弹窗、按钮、表格、Snack/Toast、状态 Banner 等）必须能同时在暗黑和白天模式下清晰显示。
- **Theme 属性绑定**：优先使用 `Theme.of(context)` 提供的颜色、字体和样式，避免手写固定颜色值。在图片或图标上需要考虑是否在不同主题下需要应用不同的 Color Filter 或透明度。

### 4. 性能 (Performance)
- **Riverpod 重绘控制**：避免全局 rebuild。使用 `ref.watch(provider.select(...))` 限制监听的属性范围。
- **异步与高频节流**：对于实时 Logcat 日志、终端输出或频繁的 ADB 物理状态查询，必须采取节流/防抖（Debounce/Throttle）限制，限制内存缓存行数，采用 `ListView.builder` 虚拟列表。
- **进程/IO 优化**：避免并发或无限循环执行 `adb shell` 命令。

### 5. 安全 (Security)
- **ADB 命令安全**：在拼接 ADB 命令和参数时，防止输入注入安全漏洞。
- **通信与数据安全**：确保跨窗口 Method Channel 传递的参数格式安全，多 Isolate 间 SharedPreferences 读写不会发生并发冲突，且持久化存储不暴露敏感数据。

