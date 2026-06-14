# Knowledge: adb-tabs-features-principles (各 Tab 功能与实现原理指南)

## 概述
本指南记录了 AdbManage 中各个工具 Tab（工具卡片页）的业务功能说明与底层技术实现原理（包括关联的 ADB 命令、系统原理与数据流设计）。在对相关业务进行重构、迭代或优化性能时，应遵循本指南的原则与规范。

---

## 1. 概览 (Overview Tab)

### 功能说明
展示当前选中 Android 设备的系统基础信息与硬件配置，包含设备名称、品牌、型号、序列号、Android ID、Android 版本与 API 级别、内核版本、处理器芯片、内存/存储容量、屏幕物理与逻辑分辨率、刷新率、字体缩放、网络 Wi-Fi SSID 以及 IP 和 MAC 地址。支持点击卡片内的任意属性值，一键复制到剪贴板。

### 底层原理与命令
1. **秒开设计（本地缓存）**：
   - 优先尝试从本地持久化（`SharedPreferences`）加载历史缓存的设备信息进行即时渲染，以防 ADB 刚连上时接口查询延迟导致页面白屏。
   - 随后异步发起 ADB 查询，并在获取到最新数据后静默刷新 UI，同步更新缓存。
2. **核心属性查询命令**：
   - **系统属性**：利用 `adb shell getprop <key>` 读取。
     - 品牌：`ro.product.brand`
     - 型号：`ro.product.model`
     - 系统版本：`ro.build.version.release`
     - API 级别：`ro.build.version.sdk`
   - **标识符**：Android ID 采用 `settings get secure android_id` 查询。
   - **处理器与内存**：解析 `/proc/cpuinfo` (处理器名称与核数) 及 `/proc/meminfo` (总物理内存 `MemTotal`)。
   - **存储空间**：运行 `df -h /data` 查询用户分区的总容量、已用空间与可用空间。
   - **屏幕参数**：
     - 分辨率：运行 `wm size` 获取物理分辨率（`Physical size`）及当前缩放分辨率（`Override size`）。
     - 屏幕密度与刷新率：运行 `wm density` 读取逻辑密度；读取 `/sys/class/graphics/fb0/measured_fps` 或 `dumpsys SurfaceFlinger` 帧率参数。
   - **网络状态**：
     - IP 地址：运行 `ip address show wlan0` 或 `ifconfig wlan0`，通过正则过滤 `inet` 后的网段。
     - MAC 地址：读取 `/sys/class/net/wlan0/address` 或 `getprop ro.boot.wifimacaddr`。

---

## 2. 控制 (Control Tab)

### 功能说明
提供与设备物理交互的面板。包含按键模拟操作（电源键、音量控制、返回键、Home键等）、嵌入式 Scrcpy 投屏启动器（配置分辨率、码率、帧率、置顶及息屏控制）、保存的 Wi-Fi 密码管理器、以及证书快速导入工具。

### 底层原理与命令
1. **物理按键模拟**：
   - 基于 `adb shell input keyevent <KEYCODE>` 注入物理按键事件。例如：
     - 返回键：`input keyevent 4` (`KEYCODE_BACK`)
     - Home 键：`input keyevent 3` (`KEYCODE_HOME`)
     - 电源键：`input keyevent 26` (`KEYCODE_POWER`)
     - 音量加/减/静音：`input keyevent 24` / `25` / `164`
2. **Scrcpy 投屏集成 (External / Embedded)**：
   - **启动控制**：利用 `Process.start` 启动宿主机已安装的官方 `scrcpy` 执行文件，传入设备 ID 参数 `-s <deviceId>`。
   - **参数配制项**：通过命令行选项控制镜像属性：
     - 限制大小：`--max-size <1024/1920>`
     - 视频码率：`--video-bit-rate <4M/8M>`
     - 息屏投屏：`--stay-awake` (投屏时开启物理保持唤醒) 或通过控制端口发送指令将 Android 设备的物理屏幕熄灭。
     - 进程生命周期：通过 Riverpod `ref.onDispose` 统一关闭底层 `scrcpy` 进程，防止僵尸后台残留。
   - **手机快捷设置弹窗**：投屏独立窗口工具栏和控制 Tab 共用 `DeviceSettingsPopup`。弹窗通过 `deviceOverviewProvider` 读取当前字体缩放、显示密度、布局边界、点按反馈状态；写入侧复用 `DeviceActionService` 的 `setFontScale`、`setDisplayDensity`、`toggleLayoutBounds`、`setShowTouches`、`setDarkMode`，执行成功后刷新 `deviceOverviewProvider`，避免重复手写 adb 命令。弹窗内的“快捷跳转”复用已有 `openDeveloperSettings`、`openWifiSettings`、`openMainSettings`、`openDeviceInfoSettings`、`openManageApplicationsSettings` 等 Android Settings Intent，作为轻量入口，不在 UI 层手写 `adb shell am start`。
   - **返回键长按强停**：投屏工具栏返回键短按仍发送 `KEYCODE_BACK`。长按时先通过 `dumpsys window | grep mCurrentFocus` 获取前台包名并在窗口内提示应用名；若继续按住且前台不是 HOME/Launcher，则执行 `am force-stop <package>`。桌面包通过系统 HOME resolve 和常见 launcher 包名识别，只提示“桌面”，不执行强停。
   - **电源键与关闭物理屏幕状态同步**：投屏工具栏的“关闭/开启设备屏幕”通过 scrcpy control message 设置 Android 物理屏幕模式，并用 `screenPowerOffProvider` 渲染 UI 状态。用户再点击电源键 (`KEYCODE_POWER`) 时，设备会离开该受控物理屏幕模式；因此电源键命令成功后必须同步将 `screenPowerOffProvider(deviceId)` 重置为 `false`，避免手机真实亮灭状态和软件图标状态不一致。
3. **已存 Wi-Fi 密码读取 (需 Root)**：
   - 依次检测三代 Android 系统配置路径，以 `cat` 命令读取其内容并在 Host 端进行 XML/conf 解析：
     - Android 11+ 路径：`/data/misc/apexdata/com.android.wifi/WifiConfigStore.xml`
     - Android 10 路径：`/data/misc/wifi/WifiConfigStore.xml`
     - 旧版本 Linux conf 路径：`/data/misc/wifi/wpa_supplicant.conf`
   - 解析其中的 `<Network>` 结构块（或 `network={...}` 块），提取 `SSID`、`PreSharedKey`/`WEPKey` 以获取 Wi-Fi 密码。
4. **证书快速导入**：
   - 参见 [证书管理机制](file:///Users/shijie/Documents/AdbManage/agent/knowledge/adb-cert-management.md)。用户证书调用 `com.android.certinstaller/.CertInstallerMain` Intent 调起系统安装；系统证书（需要 Root）使用 Subject Hash 命名并拷贝到 `/system/etc/security/cacerts/`。Android 10+ 使用 `tmpfs` 挂载，Android 14+ 需利用 `nsenter` 绑定挂载 Conscrypt APEX 目录。

---

## 3. 应用 (Apps Tab)

### 功能说明
管理 Android 设备上的所有已安装程序（包含用户应用与系统预装应用）。提供实时按拼音/首字母检索的列表及网格视图；支持提取应用高分辨率图标并进行渐进式增量渲染；提供一键启动、强行停止、清除应用数据、卸载软件以及检查与授予/撤销具体运行时敏感权限等功能。

### 底层原理与命令
1. **应用列表获取**：
   - 第三方应用列表：`adb shell pm list packages -f -3`
   - 系统预装应用：`adb shell pm list packages -f -s`
   - 返回的数据格式包含 APK 物理路径与包名，如 `package:/data/app/.../base.apk=com.example.app`。
2. **图标渐进式加载（性能优化）**：
   - **首屏秒开**：通过 `listPackages` 优先加载基础包名列表。
   - **异步提取**：后台建立独立流任务 `enrichPackagesWithIconsProgressive`，通过 `pm path <package>` 定位 APK，并利用 Host 端工具读取 APK 的 Manifest 资源文件，提取图标字节流，分批 yield 刷新 UI。
3. **生命周期与数据管理**：
   - **启动**：调用 `adb shell monkey -p <package> 1`（利用 monkey 启动默认 Activity）或 `am start -n <package>/<activity>`。
   - **停止**：`adb shell am force-stop <package>` 结束进程。
   - **清空数据**：`adb shell pm clear <package>` 重置应用状态（清空沙盒存储与数据库）。
   - **卸载**：`adb shell pm uninstall <package>`。
   - **备份/恢复应用数据**：由 `AppDataBackupService` 根据 Android API 级别和权限能力选择策略。
     - Android 11 及以下（API <= 30）：优先使用 legacy `adb backup -f <local.ab> -noapk <package>` 与 `adb restore <local.ab>`，需要用户在手机端确认，且应用 `allowBackup=false` 时可能得到空备份。
     - Android 12+（API >= 31）：legacy `adb backup` 已弱化/移除，优先使用 `adb exec-out run-as <package> tar -C /data/data/<package> -cf - .` 备份 debuggable 应用，恢复时使用 `adb exec-in run-as <package> tar -C /data/data/<package> -xf -`。
     - 非 debuggable 应用或正式包：通常需要 Root，Root fallback 会通过 `su -c tar` 在 `/data/local/tmp` 中中转 tar 包，并在恢复后执行 `chown` 与 `restorecon` 修复数据目录属主和 SELinux context。
4. **权限查看与动态配置**：
   - 查询权限：使用 `adb shell dumpsys package <package>` 输出应用的权限列表，解析 `requested permissions` 以及 `install permissions` / `runtime permissions`。
   - 动态赋权：`adb shell pm grant <package> <permission>`
   - 撤销权限：`adb shell pm revoke <package> <permission>`
5. **本地持久化缓存与秒开设计**：
   - **全量加载持久化**：在渐进式提取流（`enrichPackagesWithIconsProgressive`）执行完成时，将包含图标本地路径、展示名、签名等已 enrichment 完整的应用列表序列化为 JSON 字符串并存入 `SharedPreferences` 本地。
   - **二次秒开**：当重新打开此设备或进入 Tab 时，若本地缓存存在且非空，直接读取并显示缓存中的全量数据，实现界面零延迟瞬间加载。
   - **主动清退与回写**：在手动刷新应用列表、拖拽 APK 执行安装、卸载应用或冻结/解冻应用时，主动清除本地的 SharedPreferences 缓存，重新触发完整的元数据与图标渐进式提取，并在拉取完后自动回写更新缓存。

---

## 4. 文件 (Files Tab)

### 功能说明
设备沙盒与外部存储的文件浏览器，支持以表格和网格视图呈现。提供基础的目录跳转历史记录（前进、后退、返回上级目录、手动编辑绝对路径）、显示隐藏文件开关、目录与文件的增删查改。支持设备间的双向文件传输：提供下载（Pull）到本地、上传（Push）到设备；并深度集成桌面拖拽功能（Drag & Drop）。

### 底层原理与命令
1. **文件目录列表解析**：
   - 运行 `adb shell ls -la <path>`。
   - 对输出的 Unix 风格权限列表进行细致的正规表达式拆分，准确解析出：文件类型（`d` 目录 / `-` 普通文件 / `l` 链接文件）、大小、修改时间、文件名。
2. **文件管理命令**：
   - 创建文件夹：`adb shell mkdir -p <path>`
   - 删除目录或文件：`adb shell rm -rf <path>`
   - 拉取文件：`adb pull <remotePath> <localPath>`
   - 推送文件：`adb push <localPath> <remotePath>`
3. **桌面拖拽行为分类器（desktop_drop）**：
   - **APK 软件安装**：当拖入的文件以后缀 `.apk` 结尾时，系统判定为应用安装行为，后台异步执行 `adb install -r <apkPath>`。
   - **常规文件推送**：对于其他格式文件，判定为推送文件行为，执行 `adb push <filePath> <currentRemoteDirectory>`。
   - **状态反馈**：通过 `transferListProvider` 记录文件传输状态，提供全局浮动 loading 和 localized 成功/失败通知。

---

## 5. 日志 (Logcat Tab)

### 功能说明
实时的 Android 系统日志（Logcat）流监视器。提供日志级别的多色渲染；支持根据日志级别（V/D/I/W/E/F）、特定 Tag、包名（PID）以及任意关键词进行实时正则表达式检索过滤；支持暂停/继续（防进程泄漏）、快速清空日志缓存区以及导出当前日志文件。

### 底层原理与命令
1. **实时数据流订阅**：
   - 后台通过 `Process.start` 启动 `adb -s <deviceId> logcat -v threadtime`，返回标准输出流。
   - 监听 stdout，使用 `utf8.decoder` 转换为文本行，并按 `threadtime` 格式进行文本结构化拆分（解析出时间戳、PID、TID、LogLevel、Tag 以及日志主体内容）。
2. **内存保护与溢出规避**：
   - 为防止日志无限输出导致宿主机内存耗尽，在 Riverpod Controller (`LogcatController`) 中对缓存的日志列表长度设置了 1000 行的阈值限制，超出后自动从头部 pop 掉旧日志。
3. **无缝暂停与释放**：
   - **暂停**：UI 暂停消费 Stream，停止向前端追加列表元素，但保持底层进程继续读取，或在断开时主动终止进程，以确保良好的性能体验。
   - **释放**：利用 Widget 的生命周期或 Riverpod Provider `onDispose` 回调，强制执行 `process.kill()`。如果无响应，则使用 `ProcessSignal.sigkill` 强杀，严防 adb 进程后台残留引起系统发热。

---

## 6. 终端 (Terminal Tab)

### 功能说明
提供一个全功能的交互式 adb shell 命令行终端。支持标准输入输出流的键盘双向互动；拥有完整的终端回显与 ANSI 颜色代码解析；支持用户收藏常用命令以一键自动填入。

### 底层原理与命令
1. **进程交互通道**：
   - 启动命令：`Process.start('adb', ['-s', deviceId, 'shell'])`。
   - 管道互通：将 Flutter UI 终端视图的键盘捕获输入转换后，直接通过 `process.stdin.write` 写入进程；同时异步把 `process.stdout` 与 `process.stderr` 的流数据回显到 UI 终端面板。
2. **数据流控制**：
   - 监听进程的 `exitCode`，在进程退出时关闭终端会话并提示用户。
   - 常用命令记录（Favorite Commands）：保存在 SharedPreferences 中，支持管理和快捷输入。

---

## 7. 进程 (Processes Tab)

### 功能说明
系统级运行进程管理器，支持通过列表和搜索框定位消耗资源的进程。展示字段包含：PID、USER、CPU使用率、内存占用（RES/RSS 实际物理内存）、已执行时间以及进程名称/参数，支持按任意列名进行排序，支持选中进程一键强制终止。

### 底层原理与命令
1. **单次非阻塞快照获取**：
   - 使用 `adb shell top -b -n 1`（`-b` batch mode 批处理模式，`-n 1` 执行一次后退出）。
   - 规避使用持续输出的 `top` 导致频繁解析阻塞 UI 线程。
2. **文本表格解析器**：
   - 根据返回的首行属性表头（PID、USER、RES/RSS、CPU、TIME、ARGS 等）所在的索引位置，动态定位数据列，避免在不同 ROM（其 top 格式可能有微小偏差）上发生错位。
   - 剔除 PID 非纯数字的噪音数据。
3. **一键终止进程**：
   - 执行 `adb shell kill -9 <pid>` 强杀对应进程。

---

## 8. 网页调试 (Webpages Tab)

### 功能说明
面向混合开发（Hybrid）与移动端网页的调试分析工具。可自动扫描设备上所有的 debuggable WebView 或 Chrome 浏览器网页标签；在列表中显示其标题、原始链接、宿主包名与 PID，并判定连接状态；提供一键在宿主机 Chrome 浏览器中调起 Chrome DevTools 原生调试器、或在普通浏览器中直接打开 URL。

### 底层原理与命令
1. **调试套接字自动侦测**：
   - Android WebView 调试暴露的是 Linux Unix Sockets。运行 `adb shell cat /proc/net/unix`，寻找路径中以 `@` 开头并包含 `devtools_remote` 的套接字（如 `@webview_devtools_remote_1234`，其中 1234 为进程 PID）。
   - 解析 PID 并读取 `/proc/<pid>/cmdline` 获取对应应用的包名（如 `com.android.chrome` 或自定义 App）。
2. **动态 TCP 端口映射代理**：
   - 检索本机可用端口（`ServerSocket.bind(..., 0)` 获取动态端口）。
   - 执行 `adb forward tcp:<localPort> localabstract:<socketName>` 将本地端口转发至手机套接字。
3. **调试协议请求获取**：
   - 发送 HttpClient GET 请求至 `http://127.0.0.1:<localPort>/json/list`（对极老版本 fallback 至 `/json`）。
   - 得到网页列表的 JSON 数组，包含：`title`、`url`、`webSocketDebuggerUrl`、`id` 等。
4. **远程调试器启动机制**：
   - 拼接 DevTools URL：
     - 若选择本地调试器：`devtools://devtools/bundled/inspector.html?ws=127.0.0.1:<localPort>/devtools/page/<id>`
     - 若选择在线前端：`https://chrome-devtools-frontend.appspot.com/serve_rev/.../inspector.html?ws=127.0.0.1:<localPort>/devtools/page/<id>`
   - 跨平台调起浏览器进程：
     - macOS：`open -a "Google Chrome" <devtoolsUrl>`
     - Windows：`cmd /c start chrome <devtoolsUrl>`
     - Linux：`google-chrome <devtoolsUrl>`
5. **垃圾端口自动回收**：
   - 当设备断开连接或用户切出该 Tab 时，自动遍历 `_forwardedPorts` 缓存，执行 `adb forward --remove tcp:<localPort>` 清理转发规则，释放网络端口资源。

---

## 9. 布局分析 (Layout Tab)

### 功能说明
Android 的可视化 UI 检查器（类似于 Android Studio Layout Inspector）。支持一键同步捕获设备当前界面的红框控件树与屏幕截图；可以在交互式画布上旋转和无极缩放截图；支持“点击屏幕元素”或“点击左侧树节点”双向选中控件；展示完整的 UI 树结构及节点的 class、resource-id、package、text、bounds 等属性；支持 px / dp 单位切换，并能保存当前的 layout 结构和图片到本地。

### 底层原理与命令
1. **UI 控件树提取与解析**：
   - 执行 `adb shell uiautomator dump /data/local/tmp/uidump.xml` 将 UI 层次树以 XML 格式存储到手机临时目录。
   - 执行 `adb shell cat /data/local/tmp/uidump.xml` 读取此 XML 内容，在 Flutter 中通过 XML 解析器构建 `LayoutNode` 对象树。
2. **原始屏幕截图截取**：
   - 异步并发执行 `adb exec-out screencap -p` 实时流输出 PNG 字节。由于使用 `exec-out` 直接走标准输出获取二进制，比先 `screencap` 再 `pull` 速度快 3 倍以上。
3. **坐标映射碰撞检测（交互核心）**：
   - **Bounds 解析**：解析 XML 中节点的 `bounds="[x1,y1][x2,y2]"` 属性。
   - **多维度坐标转换**：在 Flutter 自定义 Canvas 绘制时，根据设备的物理分辨率（从截图尺寸获取）、当前 UI 容器宽度、无极缩放变换矩阵（`TransformationController`）、旋转角度（0/90/180/270度）以及设备逻辑密度（计算 DP），计算节点在当前屏幕上的真实点击响应矩形区域，从而支持精确的鼠标 Hover 高亮与点击碰撞选中。

---

## 10. 性能监控 (Performance Tab)

### 功能说明
实时监控设备和运行应用的性能状态。提供美观的折线图以展现：整体与单核 CPU 使用率、RAM 物理内存使用占比及已用 MB、前台活动应用的实时渲染帧率（FPS）、以及设备的电池电量、温度与充电状态、开机时间。

### 底层原理与命令
1. **聚合指令秒级轮询（极致优化）**：
   - 为了彻底规避高频创建 ADB 命令行进程（每秒 6-7 次 adb 启动会吞噬宿主机大量 CPU 导致界面卡顿），将所有指标的 Shell 命令合并为单条长文本发送，通过 `echo "---"` 进行结果分割：
     ```bash
     cat /proc/uptime; echo "---"; dumpsys battery; echo "---"; cat /proc/meminfo; echo "---"; dumpsys window | grep mCurrentFocus; echo "---"; cat /proc/stat | grep "^cpu"; echo "---"; ...
     ```
   - 仅通过一次 ADB 交互即能读取到所有基础及高级性能指标。
2. **FPS 计算公式**：
   - 提取前台焦点 App 的包名：
     - 通过 `dumpsys window | grep mCurrentFocus` 获取到 `mCurrentFocus=Window{... u0 com.android.settings/com.android.settings.Settings}`，提取出包名。
   - 查询包名所关联的渲染帧数：
     - 运行 `dumpsys gfxinfo <packageName> | grep "Total frames rendered:"` 读取该 App 累积的渲染总帧数 $F_{total}$。
   - 计算 FPS：
     - 在两个连续的轮询周期（时间差为 $\Delta t$）中，计算渲染帧数的差值 $\Delta F = F_2 - F_1$。
     - $FPS = \frac{\Delta F}{\Delta t}$。若前台活动窗口无变化且无刷新，则帧率判定为 0。
3. **CPU 使用率算法 (Stat 累加值差值)**：
   - 读取 `/proc/stat` 获取系统的 cpu 总计时以及各核（cpu0, cpu1...）的时间片计数器。
   - 时间片总和 $Total = user + nice + system + idle + iowait + irq + softirq$。
   - 空闲时间 $Idle = idle + iowait$。
   - 在相邻的时间 $t_1, t_2$ 刻，计算差值：$\Delta Total = Total_2 - Total_1$，$\Delta Idle = Idle_2 - Idle_1$。
   - $Usage\% = (1 - \frac{\Delta Idle}{\Delta Total}) \times 100\%$。
4. **内存与核心频率**：
   - 内存：解析 `/proc/meminfo` 的 `MemTotal` (总内存) 与 `MemAvailable` / `MemFree` / `Cached` 等，计算得出已用物理内存。
   - 频率：读取 `/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq` 以获得核心当前工作频率。

---

## 11. 网络 (Network Tab)

### 功能说明
管理反向代理端口转发规则。允许查看当前正生效的活跃代理映射；支持用户手动添加映射预设；支持在目标设备连入网络或被选中时，自动在后台应用预设的网络路由反向映射，免去开发者手动输入命令的麻烦。

### 底层原理与命令
1. **反向端口映射（ADB Reverse）**：
   - 命令执行：`adb -s <deviceId> reverse tcp:<devicePort> tcp:<localPort>`。将手机端对 `<devicePort>` 的网络请求通过 USB 传输线反向代理转发至宿主机的 `<localPort>` 端口上。
   - 适用场景：适用于手机端混合 App / 调试网页访问电脑本地开发服务器（如前端 localhost:3000、React Native 8081 端口）。
2. **反向端口管理**：
   - 列表获取：`adb -s <deviceId> reverse --list`
   - 解析格式：如 `127.0.0.1 tcp:8081 tcp:8081` 拆分为本地端口与设备端口。
   - 移除规则：`adb -s <deviceId> reverse --remove tcp:<devicePort>`。
3. **自动应用逻辑**：
   - 监听 `selectedDeviceProvider` 设备状态流。
   - 当设备检测为 online 时，自动读取保存在 SharedPreferences 中的 `PortForwardPreset`，对于标记为 `autoApply = true` 的预设，循环在后台调用 `adb reverse`。

---

## 12. 设置 (Settings Tab)

### 功能说明
管理全局应用配置和偏好设置。包含常规设置（中英文语言切换、外观主题跟随系统/浅色/深色切换、截图及录屏默认保存路径配置、缓存清理）、投屏选项设置（窗口置顶显示、音频转发开启/关闭、传输码率与最大分辨率控制），以及关于与说明信息（作者介绍、软件说明书、软件版本信息与在线检查更新）。

### 底层原理与机制
1. **全局偏好设置持久化 (AppSettings)**：
   - 数据实体由 `AppSettings` 类承载，控制状态使用 Riverpod Notifier `AppSettingsController` 进行统一管理。
   - 所有用户偏好选项（如主题模式、分辨率限制、是否音频转发等）皆通过 `SharedPreferences` 持久化存储在宿主机本地。
   - 在多窗口或子进程场景中，使用 `WindowMethodChannel` 跨引擎通知广播机制（如 `update_language`、`update_save_path`）实现全窗口的全局状态乐观更新。
2. **应用临时缓存清理机制**：
   - 临时图标缓存及预览文件通过 `CacheCleanupService` 进行深度清理。
   - 统计缓存大小与文件数量，并通过 `replaceAll` 动态刷新 localized 文案提示清理成果。
3. **版本信息与交互式更新机制 (Update Dialog)**：
   - **当前版本渲染**：在界面“关于与支持”卡片下方追加版本 Tile 呈现静态常量版本（当前为 `v1.0.0`）。
   - **交互式更新检测器 (`_UpdateCheckDialog`)**：
     - **状态流转换**：`Checking`（动画旋转器） $\rightarrow$ `HasUpdate`（显示 v1.0.1 升级日志） $\rightarrow$ `Downloading`（展示进度百分比、动态速率及下载大小） $\rightarrow$ `Installing`（加载安装） $\rightarrow$ `Success`（更新成功）。
     - **动画支持**：旋转动画采用 `RotationTransition` 及 `AnimationController` 实现，以 2 秒为周期无限循环旋转；下载进度利用 `Timer.periodic` 步进更新。
     - **双语多态设计**：包含独立的中文与英文文案对照（如 `updateSuccessDesc` 与 `downloadComplete`），消除硬编码，在语言切换时自动更新相应状态文案。
