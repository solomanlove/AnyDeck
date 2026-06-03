---
description: 多语言国际化 (l10n) 开发规范
globs:
  - "lib/app/l10n/**/*.dart"
  - "lib/**/*.dart"
alwaysApply: false
---

# 多语言国际化 (l10n) 规范

1. **文案定义**
   - 严禁在 UI 界面中直接手写硬编码的中文或英文文案。
   - 所有用户可见的文本（包含页面标题、按钮文字、提示信息、对话框内容、菜单栏选项等）都必须在本地化资源类中进行统一定义，并使用 `AppLocalizations.of(context)` 进行访问。
   - 当新增文案时，确保主窗口和子窗口的本地化文件都已同步补齐，防止解析时因键值缺失导致运行时异常。

2. **跨窗口语言同步**
   - 参见 `agent/rules/10-riverpod-state.md` 的广播规则。
   - 当用户在设置 Tab 中切换应用语言时，主 Isolate 会修改全局持久化设置并向所有已打开的子 Isolate 广播 `'update_language'` 消息。
   - 每个子窗口对应的 `MethodHandler` 必须在捕获该消息后立即更新自身 Context 内的 Language Locale 状态，以触发 UI 实时重绘。

3. **原生系统标题同步**
   - 每次语言改变或初始化新窗口时，必须调用 `DesktopWindowTitleService.setTitle(title)`，将翻译后的标题同步更新到桌面端的外壳窗口原生标题栏（例如 macOS 顶部窗口栏或 Windows 标题栏）。
   - 这涉及通过原生 Runner 插件通道（如 `MethodChannel('adb_manage/window')`）在原生端更新 Window Title，移动端或测试环境直接静默跳过。
