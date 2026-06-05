---
description: 新增页面与 Provider 开发规范及流程自检
globs:
  - "lib/**/*.dart"
alwaysApply: false
---

# 新增业务页面与 Provider 开发流程

在为 AdbManage 新增一个功能 Tab、子窗口或全新 UI 页面时，请遵循以下编排和自检流程。

## 1. 结构与位置规划
- 新增 Tab 页面应当存放在 `lib/features/dashboard/presentation/` 的对应子目录下（例如新增 layout tab 存放在 `layout/` 目录下）。
- 配套的状态管理 Provider 或后台服务应放置在 `lib/core/` 对应的业务基础设施子目录下（例如 layout 状态管理放在 `lib/core/layout_inspector/`）。
- 绝不允许直接在 UI 文件里编写复杂的后台进程或 ADB 命令拼装逻辑。

## 2. 代码编写自检清单
- [ ] **文件行数校验**：单个 Dart 文件的总行数必须控制在 **500 行以内**。超过此上限应立刻拆分子组件。
- [ ] **重复代码校验**：新增页面前必须先用 `rg` 搜索是否已有类似 Widget、Dialog、Snack、表格 Header、ADB service 方法或格式化 helper；存在可复用入口时优先接入公共工具类。
- [ ] **不可变 Widget 优先**：无内部生命周期资源的展示组件必须优先写成 `const StatelessWidget` 或纯 helper；不要为了局部 UI 状态随意引入 `StatefulWidget`。确实需要 controller / animation / focus / stream 释放时，再使用 Stateful 并在 `dispose` 中回收。
- [ ] **合理拆分与注释**：样式组件、数据处理、命令执行、Dialog/Toast 等职责必须拆开；新增公共 helper 要有一句中文职责注释，复杂异步流程要标明资源释放或性能保护点。
- [ ] **多语言适配**：所有文案是否均已通过 `AppLocalizations` 访问，不存在硬编码中英文文本。
- [ ] **多窗口适配**：如果此页面包含全局配置修改，修改处是否已经通过 MethodChannel 进行了跨 Isolate 状态更新广播。
- [ ] **进程生命周期管理**：若页面或 Provider 启动了后台子进程（如 ADB stream、录屏、投屏），是否已经在 Widget `dispose` 或 Provider `onDispose` 中执行了 `process.kill()` 彻底回收进程。
- [ ] **防重复点击与加载态**：涉及耗时 ADB 执行的按钮是否具备 Loading 拦截，或者增加了防重复点击（Debounce）处理。
- [ ] **错误边界处理**：异步操作是否都有 try-catch，并使用 `AsyncValue` 或特定 Result 类型向 UI 传递，防止后台执行崩溃导致整个桌面应用闪退。

## 3. 静态分析与规范校验
- 新增或修改代码后，必须通过命令行运行 `flutter analyze` 进行静态代码检查，确保不存在编译错误、类型未匹配或未使用的导入。
- 可以使用 `dart format .` 格式化全部 Dart 代码，保持缩进和换行与项目整体风格一致。
