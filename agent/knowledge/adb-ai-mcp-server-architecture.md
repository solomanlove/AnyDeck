# AnyDeck AI MCP (Model Context Protocol) 服务架构与集成指南

## 1. 概述与背景

**Model Context Protocol (MCP)** 是开放标准的模型上下文协议，用于让大语言模型（LLM）与外部环境、工具、系统资源进行标准化通信。
AnyDeck 内置了原生的 AI MCP Server 服务，能够将桌面端丰富的 ADB/HDC/iOS 设备管理、UI 自动化、应用生命周期、日志排查与受控 Shell 能力无缝对外输出，供 **Cursor / Claude Desktop / Antigravity / Cline / Open-Interpreter** 等各种 AI 智能体直接调用。

在桌面端 UI 架构上，AI MCP 作为独立的一级导航 Tab，位于左侧导航栏的**玩安卓 Tab 下方、设置 Tab 上方**（`tabIndex: 14`），主面板中的 MCP Tools 清单默认收起，仅展示标题、实际注册工具数量及展开箭头；点击标题或箭头展开后，支持按设备、UI/视觉、应用、日志、文件、Shell 快速分类筛选和即时搜索，无需弹窗即可直接配置各个工具的细粒度开关。

---

## 2. 核心架构设计

AnyDeck MCP 服务基于分层架构实现：

```
+-------------------------------------------------------------+
|        External AI Clients (Cursor / Claude / Agents)       |
+------------------------------+------------------------------+
                               | [JSON-RPC 2.0 via HTTP SSE]
+------------------------------v------------------------------+
|                 McpServer (核心协议路由与分发引擎)             |
|   - initialize / tools/list / tools/call / ping             |
+------------------------------+------------------------------+
                               |
+------------------------------v------------------------------+
|               McpToolRegistry (工具注册与分发中心)            |
|   - 安全拦截检查 (McpSecurityGuard)                           |
|   - 审计日志记录 (McpAuditLogNotifier)                       |
+------------------------------+------------------------------+
                               |
         +---------------------+---------------------+
         |                     |                     |
+--------v--------+   +--------v--------+   +--------v--------+
| McpDeviceTools  |   |   McpUiTools    |   |   McpAppTools   |
| (list_devices,  |   | (screenshot,    |   | (list, install, |
|  battery_info)  |   |  inspect_layout,|   |  uninstall,     |
|                 |   |  tap, swipe)    |   |  launch, stop)  |
+-----------------+   +-----------------+   +-----------------+
         |                     |                     |
+--------v--------+   +--------v--------+   +--------v--------+
|   McpLogTools   |   |  McpFileTools   |   |   McpSecurity   |
| (query_logcat,  |   | (push, pull,    |   | (高危命令模式   |
|  query_crashes) |   |  execute_shell) |   |  黑名单拦截)    |
+-----------------+   +-----------------+   +-----------------+
```

---

## 3. 支持的 MCP Tools 工具集清单

| 分类 | 工具名 | 说明 | 核心参数 |
| :--- | :--- | :--- | :--- |
| **Device** | `list_devices` | 获取当前连接的所有设备状态列表 | `forceRefresh` (bool) |
| **Device** | `get_device_detail` | 获取指定设备的详细软硬件参数 (品牌/型号/SDK/分辨率/DPI/CPU) | `deviceId` (string) |
| **Device** | `get_battery_info` | 查询电池电量、健康度与温度 | `deviceId` (string) |
| **UI** | `take_screenshot` | 截取屏幕图像并返回 Base64 编码 (供 Vision 多模态模型直接感知) | `deviceId` (string) |
| **UI** | `inspect_ui_layout` | Dump 界面 UI 控件树 XML 结构与节点属性 (uiautomator dump) | `deviceId` (string) |
| **UI** | `device_input_tap` | 在屏幕指定坐标模拟手指点击 | `deviceId`, `x`, `y` |
| **UI** | `device_input_swipe` | 在屏幕上执行滑动手势 | `deviceId`, `x1`, `y1`, `x2`, `y2` |
| **UI** | `device_input_text` | 向前台焦点输入框发送文本 (支持空格自动转义) | `deviceId`, `text` |
| **UI** | `device_press_key` | 发送 Android KeyCode 按键事件 (Home=3, Back=4, Power=26 等) | `deviceId`, `keyCode` |
| **App** | `list_installed_apps` | 列出设备上安装的应用包名与应用名 | `deviceId`, `filter` |
| **App** | `install_app` | 为设备推送并安装本地 APK | `deviceId`, `apkPath` |
| **App** | `uninstall_app` *(高危)* | 卸载指定应用 | `deviceId`, `packageName` |
| **App** | `launch_app` | 启动指定应用 (可指定 Activity) | `deviceId`, `packageName` |
| **App** | `stop_app` | 强制停止指定应用进程 | `deviceId`, `packageName` |
| **App** | `clear_app_data` *(高危)* | 清除应用所有数据与缓存 | `deviceId`, `packageName` |
| **Log** | `query_logcat` | 检索指定 Tag/Level 的实时日志 | `deviceId`, `tag`, `level`, `limitLines` |
| **Log** | `query_app_crashes` | 抓取 AndroidRuntime 崩溃与 ANR 堆栈 | `deviceId`, `limit` |
| **Log** | `clear_logcat` | 清空当前日志缓冲区 | `deviceId` |
| **File** | `list_files` | 列出设备目录下的文件元数据 | `deviceId`, `remotePath` |
| **File** | `file_push` | 上传本地文件到设备 | `deviceId`, `localPath`, `remotePath` |
| **File** | `file_pull` | 从设备拉取文件到本地 | `deviceId`, `remotePath`, `localPath` |
| **Shell** | `execute_shell` *(高危)* | 在安全沙箱保护下执行自定义 Shell | `deviceId`, `command` |

---

## 4. 客户端接入配置示例

### 1. Cursor / VSCode Cline / Antigravity / Windsurf (HTTP SSE 模式)
在客户端 `settings.json` 或 MCP 管理面板添加：
```json
{
  "mcpServers": {
    "anydeck": {
      "url": "http://127.0.0.1:8765/sse"
    }
  }
}
```
*注：AnyDeck AI MCP 采用原生常驻的 HTTP SSE 传输协议，已废弃并移除 Stdio 命令行子进程模式，避免在桌面端拉起额外的黑屏或无内容窗口。*

---

## 5. 安全防护机制 (McpSecurityGuard)

1. **高危指令拦截**：`execute_shell` 自动检测并阻止 `rm -rf /`、`wipe_data`、`fastboot flash`、`mkfs`、`format` 等破坏性指令。
2. **工具级别细粒度开关**：用户可在 AnyDeck 桌面端设置页实时禁用任意单一工具。
3. **调用审计与监控**：所有经过 MCP 的请求方法、参数、耗时与错误信息均在 `McpAuditLogsViewer` 实时展示与追溯。

## 6. SSE 服务停止与连接回收

`McpSseTransport.stop()` 先复制活动 SSE 客户端列表并清空连接 Map，再逐个关闭 `HttpResponse`。关闭连接会触发 `response.done` 回调删除 Map 项，因此不能在遍历 Map 的同时 `await client.close()`，否则多个客户端连接时可能抛出 `Concurrent modification during iteration`，导致控制台继续显示运行中。连接关闭后再关闭 `HttpServer`，成功返回后由 `McpServerNotifier.stopServer()` 更新运行状态与持久化配置。

验证：`flutter test test/mcp_sse_transport_test.dart` 使用两个真实 SSE 客户端检查停止流程；手工回归可在两个 AI 客户端接入后点击“停止服务”，确认状态变为“已停止”，再次启动后两个客户端可重新连接。此项不涉及 ADB 命令、设备状态或多窗口广播。

## 7. Tools 清单展开与收起（2026-10-31）

- **需求与入口**：AI MCP 页面中的 `McpToolsToggleList` 默认收起，点击标题栏切换展开状态，搜索框、分类筛选与工具开关均位于折叠内容区。
- **实现**：复用 Material `ExpansionTile`，设置 `initiallyExpanded: false`，由组件管理局部展开状态；`maintainState: true` 保留搜索框输入与分类条件，再次展开可继续操作。页面组件销毁后重新创建时默认收起，不新增持久化配置或全局 Provider。
- **职责边界**：折叠只影响 UI 可见性，不调用 `toggleTool`、不改变工具权限或 MCP 服务运行状态；原有工具开关仍由 `McpServerNotifier` 处理。未新增依赖、后台进程、ADB 命令、多窗口广播或投屏链路改动。
- **样式与语言**：折叠标题通过 `mcpToolsListTitle` 提供中英文文案，标题与箭头沿用项目 Theme。展开后先显示说明文字，下方分类靠左、搜索框靠右，在同一行垂直居中；窄窗口下分类可横向滚动，搜索框保持可见，避免单独占行造成留白。
- **自动验证**：新增 `test/mcp_tools_toggle_list_test.dart`，覆盖中英文 × Light/Dark 四种组合下默认收起、展开/收起、筛选与输入保留、权限切换以及服务状态刷新不主动展开。与 `test/mcp_server_test.dart`、`test/mcp_sse_transport_test.dart` 合计 13 项测试通过；变更 Dart 文件定向 `flutter analyze` 通过。
- **人工验证边界**：未启动桌面应用。可进入 AI MCP，确认标题和工具数量可见、工具清单默认隐藏；展开后输入搜索、选择分类、修改工具权限，再收起/展开检查筛选和权限保留。

- **同排布局回归（2026-10-31）**：上述 Widget 测试补充 1100、860、600 logical pixels 三种宽度，验证分类与搜索框中心对齐、搜索框不超出窗口以及无布局溢出；中英文 × Light/Dark 共 4 项通过，变更 Dart 文件定向静态检查通过。未启动桌面应用。
