# Skill: adb-similarity-check (页面/组件同质化检查)

## 概述
本技能旨在保持 AdbManage 代码库的精简与高内聚性，审查是否存在重复的页面模板、同质化的后台进程处理、或在不同 Tab 页面中重复造轮子的问题。

## 审查步骤

1. **核对核心 ADB 工具封装**
   - 绝不允许手写重复的 `Process.run('adb', ...)`。
   - 所有标准设备行为（获取设备列表、发送 Shell 命令、截图、装包、启停录屏、获取 App 列表及详情等）都应由 `lib/core/adb/adb_service.dart` 统一提供服务。

2. **核对公共 UI 组件**
   - **加载态与空状态**：核查不同 Tab 下加载中的转圈动效和空数据占位。应统一复用公共组件（如自定义的 Loading 控件），保持动画节奏、主题配色（明暗模式）与微动效行为完全一致。
   - **弹窗与输入框**：核对模拟器配置、ADB 连接端口输入、命令确认弹窗等。优先复用标准 Dialog Wrapper 或是自定义 Input Box，确保交互风格和圆角（BorderRadius）、内边距（Padding）符合全局 UI 设计。

3. **核对设置与同步逻辑**
   - 检查是否有在多个地方重复解析 MethodChannel 命令或单独实现跨窗口通知的现象。
   - 配置与设置相关的操作应该一律收口到 `lib/app/settings/app_settings_controller.dart`，只在 Provider 中实现，严禁在页面 UI 逻辑中随意新增独立的广播调用。
