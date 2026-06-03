# Skill: adb-project-context (项目上下文索引)

## 概述
本技能用于快速梳理 AdbManage 的目录分工、技术栈依赖、核心全局 Provider 资产以及风险边界。任何需要对项目整体结构做变更或新增子包时，需以此技能为核心。

## 目录分工与职责划分

```text
lib/
├── app/                  # 框架主导层
│   ├── l10n/             # 多语言定义 (app_localizations.dart)
│   ├── router/           # GoRouter 页面路由配置
│   ├── settings/         # 持久化全局设置 (SharedPreferences & AppSettingsController)
│   ├── theme/            # Material Theme 配色及样式
│   └── window/           # 桌面端原生窗口注册与控制 (desktop_window_manager_service.dart)
│
├── core/                 # 核心基础设施与无状态 ADB/scrcpy 服务包装
│   ├── adb/              # adb 进程调配、截图、录制封装 (adb_service.dart, adb_device.dart)
│   ├── process/          # 环境变量与路径解析 (tool_path_resolver.dart)
│   ├── providers/        # 全局状态管理 (app_providers.dart)
│   ├── scrcpy/           # 嵌入式投屏逻辑 (embedded_scrcpy_service.dart)
│   └── terminal/         # ADB 交互终端会话管理
│
└── features/             # 业务实现（以主页面 Dashboard 为主）
    └── dashboard/
        └── presentation/ # Dashboard 各个子 Tab 的 UI 实现（如 logcat, screenshot, layout 等）
```

## 全局核心 Provider 清单
- `windowIdProvider` (Provider<int>): 记录当前 Isolate 所在的窗口 ID（主窗口固定为 0）。
- `appSettingsProvider` (NotifierProvider): 管理多语言、明暗主题、投屏最前配置。
- `adbServiceProvider` (Provider): 提供 `AdbService` 实例。
- `deviceListStreamProvider` (StreamProvider): 监听已连接的 ADB 设备列表流。
- `selectedDeviceProvider` (StateProvider): 当前用户选中的操作设备。
- `screenPowerOffProvider` (StateProvider): 设备屏幕物理关闭状态同步（用于投屏时息屏）。

## 核心注意事项
- **多 Isolate 独立性**：各个窗口由不同的 Isolate 执行，内存独立，无法通过直接读取 Provider 实例实现跨窗口数据同步。
- **命令行解析风险**：对 `adb` 输出结果的解析依赖特定正则或文本拆分（如解析 `adb devices -l`），在升级或第三方设备定制时可能有偏差，必须在 `core/adb` 集中处理并记录日志。
