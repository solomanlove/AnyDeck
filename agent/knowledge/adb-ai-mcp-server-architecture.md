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
| **App** | `list_app_instances` | 查询 Android 应用所在的用户空间，包括双开实例 | `deviceId`, `packageName` |
| **App** | `install_app` | 为设备推送并安装本地 APK | `deviceId`, `apkPath` |
| **App** | `uninstall_app` *(高危)* | 卸载指定应用 | `deviceId`, `packageName` |
| **App** | `launch_app` | 启动应用，Android 支持指定用户，HarmonyOS 使用 EntryAbility | `deviceId`, `packageName`, `userId`（仅 Android，可选） |
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
3. **调用审计与监控**：通过协议校验的普通请求与工具调用在 `McpAuditLogsViewer` 展示方法或工具名、接入平台、时间、耗时与成功/失败状态，点击记录可查看脱敏参数和响应摘要。最近 200 条摘要持久化，重启后恢复；参数详情仅保留在当前进程内存中。通知与心跳不占用历史。

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


## 9. 生命周期与凭据迁移异常回归（2026-11-10）

- 新增 socket 回归复现并修复两个竞态：连续启动生成未持有的 listener、启动尚未完成时停止却在返回后继续运行。`McpServer` 现在串行处理启停，同配置重复启动直接返回；启动失败不会阻断后续关闭或重试。
- 凭据迁移统一放在受保护的初始化流程中。损坏 JSON、读取异常、写入返回 false 或抛错都不开放入口；不静默覆盖损坏的旧配置，不向 UI 暴露未成功保存的 Token。失败提示提供中英文翻译。
- `test/mcp_lifecycle_test.dart` 两项、`test/mcp_config_initialization_test.dart` 三项通过；与已有 MCP/iOS 回归及官方 SDK 互操作测试合计 46 项通过。变更文件定向 `flutter analyze --no-pub` 无问题。
- `flutter build macos --debug --no-pub` 在本机因 Xcode 仅提供 arm64e host destination 失败；改用下列 generic macOS destination 完成 arm64 Debug 构建。仅在临时目录输出，无项目架构配置变更；构建产生的 Podfile.lock checksum 改动已还原。

```bash
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination 'generic/platform=macOS' -derivedDataPath /tmp/anydeck-mcp-build-20261110 \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
```

- 对该临时产物使用项目 Debug entitlements 进行本地 ad hoc 签名并通过 deep/strict 验签，实际启动后检查 AI MCP 页面：三平台配置、34 个工具、默认收起及展开、iOS 平台筛选通过。临时实例已退出。未在页面修改端口、启停真实服务、轮换凭据或改变工具权限；8765 已由另一实例占用时显示启动失败的真实错误，未中止现有实例。
- 用户确认暂时没有 iPhone，iOS 设备侧验收继续保留；当前结论只证明自动路由、协议互操作、UI 与编译，不代表 iPhone 上 WDA/IPA/AFC/进程/syslog 已验收。

## 10. iPhone 真机续验与开发者镜像缓存（2026-11-10）

- 用户连接“66的 iPhone”后恢复验收；目标为 iPhone X / iOS 16.7.16。存在另一台 iPhone 时，所有设备命令始终指定目标 UDID，不切换设备。
- 已通过真实 MCP：设备详情、应用枚举（安装 WDA 前 207 个应用）、syslog 最多 10 行采样、1125 × 2436 PNG 截图、45 个进程读取。WDA 未启动时状态如实返回 `ready=false`，geometry 返回不可用错误。
- 真机复现截图恢复失败：GUI 工作目录只读，go-ios `image auto` 默认创建 `./devimages`。新增 `IosDeveloperImageCache`，由 `IosCommandService.run` 在自动挂载前创建绝对缓存并传入 `--basedir`；截图和 WDA 无需分别拼接路径。显式传入的 `--basedir` 保持原样，普通命令不创建缓存。
- macOS 缓存为 `~/Library/Caches/AnyDeck/ios/devimages`；Windows 使用 `LOCALAPPDATA`，Linux 使用 `XDG_CACHE_HOME` 或 `~/.cache`，缺失时回退系统临时目录。路径以单独参数传递，支持空格，不修改进程级工作目录。
- `IosDeviceService.mountDeveloperImage` 的挂载和结果查询同时改用上述短命令执行器：下载允许五分钟，查询保留默认超时，超时会终止/必要时强杀子进程。缓存创建异常返回失败，不启动 CLI。
- 首次镜像下载因网络超时留下不完整文件；本次重新下载完整镜像，使用 `hdiutil verify` 校验后替换本次失败的缓存。目标解锁、开启 Developer Mode 后挂载成功；锁屏返回 `PasswordProtected`，不视为挂载成功。go-ios 的零退出码不能覆盖日志中的 ERROR。
- 自动回归：缓存、单文件下载、截图、WDA 宿主/生命周期/超时恢复、命令解析、平台工具和 iOS 路由合计 42 项通过；六个变更 Dart 文件定向 analyze 无问题。缓存回归包含真实子进程从 `/` 运行、空格路径、显式缓存参数和缓存创建失败。
- AFC 实测发现 go-ios 的 `--dstPath` 表示目标目录，直接传入“另存为”的完整路径会生成同名目录。`pullFile` 现在在保存位置的父目录下建立临时目录，命令完成后确认真实单文件存在，再原子重命名至指定文件名；命令失败或产物缺失时保留旧文件，finally 清理临时目录。目录下载明确拒绝，空文件合法。MCP 说明明确 `localPath` 需含文件名，成功结果返回实际路径和 `byteLength`。

### 设备侧验收结果与边界

| 项目 | 实测证据 |
| --- | --- |
| WDA 部署 | 使用用户指定的 Team，通过定向设备 provisioning 构建，Runner 安装完成；首次 generic 构建的 profile 未包含目标设备，不能据此声称安装成功 |
| WDA 状态与坐标 | 真实会话 `ready=true`，375 × 812 point、PORTRAIT；对应 1125 × 2436 截图，两个方向均为 3 倍换算 |
| 布局与点击 | MCP 返回 Accessibility XML；点击桌面搜索后，截图和 XML 均显示搜索输入框；使用 UI Tree 中清除按钮的 point 边界执行点击 |
| 文本输入 | 输入 `AnyDeck MCP 验收`，截图与输入框 XML `value` 均精确匹配；随后清除测试文本 |
| 滑动与 Home | 设置页滑动前后截图确认内容位置变化；从设置页调用 Home 后，截图确认返回桌面。Spotlight 已属于 SpringBoard 时，WDA homescreen 不保证收起搜索覆盖层 |
| IPA 安装 | 将已完成目标设备签名的 Runner 打包为 IPA，通过真实 MCP `ios_install_ipa` 重装成功；再次枚举确认目标 Bundle ID 存在 |
| AFC | 仅访问本次安装的 Runner container。上传后设备端目录可见；修复后的下载落到指定本地文件，42 字节，两端 SHA-256 均为 `52fb77ccec25f65ddbf14c9fa346ebb5e978b5db289bca0af641d2cf3e3da578`；临时目录无残留，远端测试文件已移除 |

- 交互与修复后的文件下载通过临时、鉴权、loopback 的真实 `/mcp/ios` 服务验证，复用产品 registry、CLI 与 `IosWdaHost`；仅在验收宿主中把 Flutter MethodChannel 桥接替换为直接调用宿主，不 Mock 设备响应。初次临时宿主误用了 Widget test 的 HTTP 拦截，移除该测试环境拦截后通过；这不是产品网络故障。
- 验收结束关闭临时 MCP listener、WDA CLI 和 USB proxy，保留签名 Runner 供后续使用。未替换正在运行的 `/Applications/AnyDeck.app`；代码修复需重新构建安装后生效。
- 本轮覆盖 iOS 16.7.16 竖屏；iOS 17+ tunnel、横竖屏切换、锁屏控制、音量及用户 App 卸载未验收。WDA 状态查询仍不会隐式启动 Runner。

CLI 参数依据：[go-ios image auto](https://github.com/danielpaulus/go-ios/blob/main/main.go)。

## 11. 调用审计漏记与重启历史修复（2026-11-17）

- **需求**：AI 客户端已调用工具，AI MCP 页面却显示“暂无调用记录”。已有实现仅在工具调用分支和异常分支记录日志，`initialize`、`server/discover`、`tools/list` 等正常请求直接返回而漏记；日志只在 `McpAuditLogNotifier` 内存中，重新运行应用后全部丢失。
- **验证所得**：真实 HTTP 回归确认，未订阅审计页面时，原有工具调用回调可更新 Provider；不能将现象直接归因于页面漏刷新。历史未曾落盘的旧调用无法补回；独立进程的调用仍由实际监听端口的实例负责记录。
- **统一边界**：`McpServer.handleRequest` 依据最终 JSON-RPC/tool 响应在 `finally` 中记录一次，包含成功、业务失败和未知方法。`Stopwatch` 统计耗时，通知与 `ping` 不进入审计；审计回调异常不能替换响应或重复执行工具。HTTP 鉴权/协议检查拒绝的请求不进入此业务审计。
- **历史归属**：`features/mcp/data/mcp_audit_log_store.dart` 使用现有 SharedPreferences 保存 `mcp.auditLog.v1`，按新到旧保留最近 200 条。Server 初始化先恢复历史再开放 listener；调用与历史恢复并发时合并快照，恢复未完成时清空不会让旧记录复活。写入串行并合并等待快照，停止服务时等待写入；清空操作同时更新持久化历史。
- **隐私和故障**：磁盘仅保存时间、方法、工具名、平台、耗时和成功/失败状态，不保存参数详情、设备 ID、错误正文、输入文本、Shell、文件路径或凭据。存储失败保留内存日志，记录异常类型，后续调用可重新保存；强制终止进程前尚未完成的异步写入仍可能丢失。
- **改动边界**：不新增设备轮询、CLI 执行、依赖、窗口广播或投屏会话；复用现有审计页面、Theme 和文案。
- **回归**：新增三个审计测试文件，覆盖四个 HTTP 入口在页面未订阅时的成功调用、失败仅记一次、协议请求、回调异常隔离、重建恢复、200 条上限、恢复/清空/写入并发、存储失败后恢复与损坏历史。相关 MCP 协议、平台路由、启停、凭据和 SSE 测试合计 45 项通过，8 个变更 Dart 文件定向 `flutter analyze --no-pub` 无问题。未构建或运行修复后的桌面应用，真实窗口验收待重新构建后进行。

```bash
flutter test --no-pub test/mcp_audit_dispatch_test.dart test/mcp_audit_history_test.dart test/mcp_audit_pipeline_test.dart test/mcp_server_test.dart test/mcp_config_initialization_test.dart test/mcp_platform_endpoints_test.dart test/mcp_platform_tools_test.dart test/mcp_lifecycle_test.dart test/mcp_sse_transport_test.dart
```

人工回归：客户端执行 `tools/list` 和一次工具调用 → 打开 AI MCP 核对记录及状态 → 正常停止并重新打开 AnyDeck 核对历史 → 清空日志后再次重开，确认旧记录不再出现。多实例运行时先确认客户端端口由当前窗口对应的进程持有。

## 12. 调用审计详情（2026-11-25）

- 在 AI MCP 的调用审计日志中点击任意记录，可查看请求方法、工具名、接入平台、本地日期时间、耗时与状态。详情可滚动和选择复制，参数以多行 JSON 显示。
- `McpServer.handleRequest` 从最终响应提取协议版本、`server/discover` 的服务端支持版本、列表结果数量、JSON-RPC 错误码或工具失败标记。工具参数按已注册工具的声明收集，输入文本、Shell、本机文件路径及异常结构或超长值显示为 `[redacted]`，接入平台取自服务端路由。
- 历史仍使用 `mcp.auditLog.v1`，新记录增加可选响应摘要。旧记录可查看原有字段，新旧历史均只保留摘要。脱敏工具参数留在当次 AnyDeck 进程的内存中。
- 回归覆盖详情弹窗的窄窗滚动、中英文与明暗主题、最终响应到审计 Provider 的 HTTP 链路，以及旧版历史恢复和磁盘脱敏。人工验收时，分别点击一次 `server/discover`、一次成功工具调用和一次失败调用，然后重启 AnyDeck 核对历史摘要。

## 13. Android 双开应用发现与启动（2026-11-25）

- Android 和兼容入口的 MCP `instructions` 引导客户端先通过 `list_devices` 获取在线设备 ID，再用 `list_app_instances` 查询应用包，选择与用户要求一致的实例。启动时将该实例的 `userId` 连同 `deviceId` 和 `packageName` 传给 `launch_app`，然后检查前台画面。
- `list_app_instances` 使用 `cmd user list -v` 读取设备提供的名称和类型，例如小米 HyperOS 的 `XSpace` 和 `profile.CLONE`。无法识别详细输出时使用 `pm list users`，返回用户 ID、名称和可用的类型。逐个执行 `pm list packages --user <ID> <包名>` 做精确匹配。部分用户查询失败时，`unavailableUserIds` 标明这些用户的安装状态未知。
- 指定 `userId` 时，先在该 Android 用户下解析 LAUNCHER Activity，再通过 `am start -W --user <ID>` 启动该入口，检查 Activity Manager 的状态。解析或启动失败会返回工具错误。省略 `userId` 时沿用既有启动流程。工具复用现有平台校验、分类开关、同设备命令队列与 ADB 超时。
- 自动回归在 `test/mcp_android_app_instances_test.dart`，覆盖工具发现和指引、动态用户 ID、精确包名、旧系统回退、查询受限、错误参数、启动超时和 Android / HarmonyOS 默认启动。人工验收在启用双开的 Android 真机调用查询及显式启动，核对前台窗口的用户 ID 与所选实例一致。
