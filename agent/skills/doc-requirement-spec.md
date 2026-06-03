# Skill: doc-requirement-spec (需求交接文档)

## 概述
本技能用于为 AdbManage 的新功能、大版本重构或第三方对接生成标准的技术交接文档，确保后续接手的开发者或 AI 助手能无缝理解代码变更逻辑和配置变更。

## 交接文档模板 (Markdown)

```markdown
# 功能技术规格与交接说明：[功能名称]

## 1. 业务目标与需求简述
- 解决什么问题
- 用户使用路径

## 2. 架构与改动范围说明
- **改动文件列表**：(提供 clickable file links)
- **新引入依赖/插件**：
- **新增 Provider 及其状态描述**：

## 3. 核心设计决定 (Design Decisions)
- [例如：为什么使用 desktop_multi_window 独立窗口而不是 Overlay]
- [例如：对 scrcpy 触控坐标映射所做出的算法选择]

## 4. 跨 Isolate / 多窗口通讯变更 (如果有)
- **广播 MethodChannel 方法名**：`xxx`
- **参数传递格式**：`{...}`
- **广播方向**：`[主窗口 -> 子窗口]` 或 `[子窗口 -> 主窗口]`

## 5. 后台进程与生命周期 (如果有)
- **执行命令**：`adb shell xxx`
- **生命周期回收挂载点**：[例如：lib/core/xxx_provider.dart 的 onDispose]

## 6. 后续迭代建议
- 遗留的性能风险或受限于 Android 版本暂时未支持的特性。
```
