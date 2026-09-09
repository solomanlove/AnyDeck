# AnyDeck AI MCP (Model Context Protocol) 服务架构与集成指南

## 1. 概述与背景

**Model Context Protocol (MCP)** 是开放标准的模型上下文协议，用于让大语言模型（LLM）与外部环境、工具、系统资源进行标准化通信。
AnyDeck (AdbManage) 内置了原生的 AI MCP Server 服务，能够将桌面端丰富的 ADB/HDC/iOS 设备管理、UI 自动化、应用生命周期、日志排查与受控 Shell 能力无缝对外输出，供 **Cursor / Claude Desktop / Antigravity / Cline / Open-Interpreter** 等各种 AI 智能体直接调用。

在桌面端 UI 架构上，AI MCP 作为独立的一级导航 Tab，位于左侧导航栏的**玩安卓 Tab 下方、设置 Tab 上方**（`tabIndex: 14`），并在主面板中以平铺卡片的形式完整展开全部 22 个工具集（支持按设备、UI/视觉、应用、日志、文件、Shell 快速分类筛选和即时搜索），无需弹窗即可直接配置各个工具的细粒度开关与运行参数。

---

## 2. 核心架构设计

AnyDeck MCP 服务基于分层架构实现：

```
+-------------------------------------------------------------+
|        External AI Clients (Cursor / Claude / Agents)       |
+------------------------------+------------------------------+
                               | [JSON-RPC 2.0 via SSE/Stdio]
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

### 1. Cursor / VSCode Cline / Antigravity (HTTP SSE 模式)
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

### 2. Claude Desktop (Stdio 管道模式)
在 `~/Library/Application Support/Claude/claude_desktop_config.json` 中配置：
```json
{
  "mcpServers": {
    "anydeck": {
      "command": "/Applications/AnyDeck.app/Contents/MacOS/AnyDeck",
      "args": ["--mcp-stdio"]
    }
  }
}
```

---

## 5. 安全防护机制 (McpSecurityGuard)

1. **高危指令拦截**：`execute_shell` 自动检测并阻止 `rm -rf /`、`wipe_data`、`fastboot flash`、`mkfs`、`format` 等破坏性指令。
2. **工具级别细粒度开关**：用户可在 AnyDeck 桌面端设置页实时禁用任意单一工具。
3. **调用审计与监控**：所有经过 MCP 的请求方法、参数、耗时与错误信息均在 `McpAuditLogsViewer` 实时展示与追溯。
