# AnyDeck AI MCP (Model Context Protocol) 服务架构与集成指南

## 1. 概述与背景

**Model Context Protocol (MCP)** 是开放标准的模型上下文协议，用于让大语言模型（LLM）与外部环境、工具、系统资源进行标准化通信。
AnyDeck 内置了原生的 AI MCP Server 服务，能够将桌面端丰富的 ADB/HDC/iOS 设备管理、UI 自动化、应用生命周期、日志排查与受控 Shell 能力无缝对外输出，供 **Cursor / Claude Desktop / Antigravity / Cline / Open-Interpreter** 等各种 AI 智能体直接调用。

在桌面端 UI 架构上，AI MCP 作为独立的一级导航 Tab，位于左侧导航栏的**帮助中心 Tab 下方、设置 Tab 上方**（`tabIndex: 14`），主面板中的 MCP Tools 清单默认收起，仅展示标题、实际注册工具数量及展开箭头；点击标题或箭头展开后，支持按设备、UI/视觉、应用、日志、文件、Shell 快速分类筛选和即时搜索，无需弹窗即可直接配置各个工具的细粒度开关。

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
| **UI** | `device_press_key` | 使用兼容 KeyCode；iOS 限 Home/音量/锁屏 (Home=3, Back=4, Power=26 等) | `deviceId`, `keyCode` |
| **App** | `list_installed_apps` | 列出设备上安装的应用包名与应用名 | `deviceId`, `filter` |
| **App** | `install_app` | 为设备推送并安装本地 APK | `deviceId`, `apkPath` |
| **App** | `uninstall_app` *(高危)* | 卸载指定应用 | `deviceId`, `packageName` |
| **App** | `launch_app` | 启动应用；HarmonyOS 当前使用 EntryAbility | `deviceId`, `packageName` |
| **App** | `stop_app` | 强制停止指定应用进程 | `deviceId`, `packageName` |
| **App** | `clear_app_data` *(高危)* | 清除应用所有数据与缓存 | `deviceId`, `packageName` |
| **Log** | `query_logcat` | 检索指定 Tag/Level 的实时日志 | `deviceId`, `tag`, `level`, `limitLines` |
| **Log** | `query_app_crashes` | 读取 AndroidRuntime 错误片段，不代表完整崩溃历史或 ANR | `deviceId`, `limit` |
| **Log** | `clear_logcat` | 清空当前日志缓冲区 | `deviceId` |
| **File** | `list_files` | 列出设备目录下的文件元数据 | `deviceId`, `remotePath` |
| **File** | `file_push` | 上传本地文件到设备 | `deviceId`, `localPath`, `remotePath` |
| **File** | `file_pull` | 从设备拉取文件到本地 | `deviceId`, `remotePath`, `localPath` |
| **Shell** | `execute_shell` *(高危)* | 执行 Android Shell；默认高危防护阻止调用，黑名单不构成沙箱 | `deviceId`, `command` |

---

## 4. 兼容 SSE 客户端接入配置示例

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
*2026-11-09 起优先使用下文的平台 Streamable HTTP 入口。旧 `/sse` 可显式启用用于迁移；产品仍不创建 Stdio 子进程。*

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


## 8. Android / HarmonyOS / iOS 平台入口（2026-11-09）

### 需求与实现

一个 AnyDeck 主进程和一个 loopback HTTP listener 承载三个逻辑 MCP Server。`McpRegistryFactory` 收口主窗口和独立 Server 的装配，复用 ADB/HDC/go-ios 服务；不新增设备后台轮询或投屏会话，不改动多窗口 MethodChannel。

| 名称 | URL（默认端口） | 工具范围 |
| --- | --- | --- |
| Android_MCP | `http://127.0.0.1:8765/mcp/android` | 设备、UI、APK、应用、Logcat、文件、受限 Shell |
| HarmonyOS_MCP | `http://127.0.0.1:8765/mcp/harmony` | 设备、截图/布局、HDC 输入、应用、HAP/HSP、hilog、文件 |
| iOS_MCP | `http://127.0.0.1:8765/mcp/ios` | 设备、截图/WDA、应用/IPA、AFC、WDA 状态/尺寸、进程、syslog |

- `McpToolDefinition.platforms` 同时约束 `tools/list` 和 `tools/call`。工具名在各 Server 内保持稳定，客户端配置名采用 `anydeck-android`、`anydeck-harmony`、`anydeck-ios`；聚合客户端应保留 Server 命名空间。
- 设备发现合并三个平台，缓存两秒，并合并进行中的扫描；`forceRefresh` 会请求新扫描。在线 ID 存在歧义、设备未知、离线或平台不符时，在进入 CLI 前拒绝。某个平台工具链失败不删除其他平台设备。
- 输入参数先校验必填项、类型、枚举、数值和包名格式。同一设备的调用串行执行，防止跨客户端布局临时文件与 UI 输入互相覆盖；不同设备可并发。
- HarmonyOS 应用工具传入 `isHarmony`，文件工具复用 `FileManagerService`，UI tap/swipe/text 走 HDC。`harmony_install_app` 安装本机 HAP/HSP；`query_hilog` 读取当前缓冲区最多 500 行。HarmonyOS 概览返回真实原始信息并标记 `partial`；当前应用启动依赖既有默认 `EntryAbility`。
- iOS 新增 `ios_get_automation_status`、`ios_get_screen_geometry`、`ios_list_processes`、`ios_query_syslog`。WDA 不在线时返回执行错误，不隐式安装或启动。syslog 只采样随后最多三秒，最多 500 行、256K 字符，stderr 上限 8K 字符，finally 中终止/必要时强杀子进程并回收订阅。

### 面向大模型的契约

- Server `instructions` 指导模型先枚举真实 ID、先观察后操作、操作后验证；设备文本/日志仅视为数据。Tool description 包含支持平台、前置条件与边界。
- Tool schema 增加 `annotations` 和 object `outputSchema`；输出增加 `structuredContent`。旧兼容调用保留 `data` 字段。
- 截图以标准 `image` content 返回，Base64 不再混进模型的 JSON 文本或 `structuredContent`。同时返回图片像素宽高、真实 MIME、`coordinateSpace=image_pixels` 与 `inputCoordinateSpace`。
- iOS WDA 输入为 point。模型必须读取 `ios_get_screen_geometry`，按实际截图宽高换算；横竖屏后重新读取。UI Tree 保留 WDA point，不能直接作为截图像素使用。
- `query_app_crashes` 仅表示当前 AndroidRuntime 日志片段，对失败明确报错，支持片段级包名过滤，不承诺完整 ANR 报告。

### 协议、安全与迁移

- 新入口支持 `2026-07-28` 逐请求元数据及 `2025-11-25` initialize 客户端。新版实现 `server/discover`、`resultType`、私有且即时过期的列表缓存提示，并校验版本、`Mcp-Method`、`Mcp-Name` 与请求体一致；GET/DELETE 不创建兼容 SSE 会话。
- 当前不发布变更订阅，`listChanged=false`；权限改变后，客户端需重新读取工具清单或重连。不要声称已实现 subscriptions、OAuth 或完整远程托管能力。
- 监听仅允许 loopback。Host/Origin 校验、明确的 URL 路由、1 MiB 请求体上限、读取超时及最多四个并发平台 HTTP 请求保护入口。平台 Token 使用 32 字节安全随机数，各入口独立校验 Bearer，禁用/轮换即时生效，不重启其他入口。
- 平台 Token 持久化在已有本地 MCP 配置中，页面不显示明文，只有用户复制配置时包含 Authorization。当前是本机凭据方案，未接入 Keychain 或 OAuth。
- 高危防护开启时真正阻止卸载、清数据和任意 Shell；关闭后仍保留 Shell 黑名单。工具开关与分类权限在执行时再次检查。审计保留平台、工具、耗时与结果，屏蔽输入文本、Shell 和本机文件路径，错误日志仅记录错误类型。
- 新配置默认关闭兼容 SSE；已有 v1 配置缺少 `enableLegacy` 时迁移为开启，保留旧配置可用性。兼容入口允许所有平台且沿用旧鉴权设置，UI 提供独立开关。平台 Token 不等于兼容入口的凭据，关闭兼容入口可收口到三个独立权限范围。
- 兼容 SSE 使用服务端随机 sessionId，无效 ID 在执行前拒绝，不回退到最后连接的客户端。响应关闭缓冲，立即发送 endpoint 事件；SSE 响应只发往匹配连接，不重复发送到 POST body。停止沿用先复制连接集合再关闭的回收顺序。

### 配置、测试与回归

进入 AI MCP → 启动服务 → 在对应平台复制配置。复制内容包含该入口 Token；在不再使用时关闭入口或更新凭据。工具清单增加平台筛选，并保留默认收起、搜索和分类状态。新增配置文案覆盖中文/英文，新增组件使用 Theme。

自动验证（2026-11-09）：

- 9 个 MCP / iOS 测试文件共 41 项通过，覆盖跨入口工具/设备拒绝、同 ID 并发、凭据校验/轮换、Origin、Header、兼容配置迁移、队列失败释放、图片 content、HDC 路由与 syslog 回收，以及中英文 × Light/Dark 的配置和筛选。
- 使用官方 `@modelcontextprotocol/client@2.4.0` 实际连接三个平台，分别验证 modern/legacy Streamable HTTP 的 list/call，以及旧 SSE list；SDK 安装在临时目录，不加入产品依赖。
- 真机只读回归：两台 Android 和一台 HarmonyOS 的发现、实时概览、截图和应用读取通过；HarmonyOS hilog 读取通过。
- 当前无在线 iOS 真机：WDA 实际输入、IPA/AFC、进程和 syslog 的设备侧验收仍待完成。安装/卸载、清数据、文件写入及 UI 输入未在用户真机上自动执行；其路由和防护有自动测试覆盖。
- 未启动桌面应用；新 UI 已做 Widget 回归，桌面交互验收仍可在实际应用中补测。

可复现命令：

```bash
flutter test --no-pub test/mcp_platform_endpoints_test.dart test/mcp_platform_tools_test.dart test/mcp_platform_config_test.dart test/mcp_server_test.dart test/mcp_device_tools_test.dart test/mcp_sse_transport_test.dart test/ios_capability_route_test.dart test/mcp_tools_toggle_list_test.dart
npm install --prefix /tmp/anydeck-mcp-sdk @modelcontextprotocol/client@2.4.0
ANYDECK_MCP_SDK=/tmp/anydeck-mcp-sdk/node_modules/@modelcontextprotocol/client/dist/index.mjs flutter test --no-pub test/mcp_sdk_interop_test.dart
ANYDECK_MCP_DEVICE_SMOKE=1 flutter test --no-pub test/mcp_device_smoke_test.dart
```

官方依据：[Tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools)、[Streamable HTTP](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)、[2026-07-28 Schema](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/schema/2026-07-28/schema.ts)。
