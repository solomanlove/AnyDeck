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
