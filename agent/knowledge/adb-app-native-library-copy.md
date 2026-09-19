# 应用原生库名称复制机制

## 功能目标

应用管理详情的“原生库”Tab 在每个 `.so` 库名右侧提供复制按钮。点击后仅把完整库名写入系统 Clipboard，不包含库大小、识别标签或说明，并通过 Dashboard 统一轻提示反馈复制成功。

## 实现范围

- `dashboard_app_details_tabs_2.dart`：在库名标题行接入复制按钮，复用 `Clipboard`、`DashboardSnack` 与现有 `copy` / `copySuccess` 本地化文案。
- `dashboard_app_native_library_rules.dart`：承载常用原生库识别规则，使详情 Tab UI 文件保持在 500 行以内；规则匹配行为不变。
- `dashboard_screen.dart`：注册原生库规则 part 文件。

该功能是纯本地 UI 操作，不执行 ADB 命令、不新增 Provider，也不涉及主窗口与子窗口之间的 MethodChannel 同步。

## 交互与边界

1. 复制内容使用解析后的 `libName`，例如 `libflutter.so`，不会携带原始条目中的 `:size` 后缀。
2. 复制按钮使用主题默认前景色，适配 Light / Dark Mode。
3. Clipboard 写入完成后才显示成功提示；如果 Widget 已销毁，不再展示 Overlay。
4. 搜索、动态库识别、大小展示与 `extractNativeLibs` 展示逻辑保持不变。

## 验证方案

1. 静态检查：执行 `flutter analyze`，确认 part 注册、Clipboard API 与 Widget 类型无错误。
2. 正向用例：在原生库列表点击任一复制图标，粘贴结果应与该行 `.so` 库名完全一致。
3. 数据边界：带大小数据的条目只复制库名，不复制大小；未知动态库同样支持复制。
4. UI 回归：分别在 Light / Dark Mode 检查图标可见性，并确认长库名、库大小和复制按钮没有溢出。

## 验证边界

本次不启动 Flutter Desktop 项目；Clipboard 的真实系统粘贴结果和界面布局需在 macOS App 中手工验收。
