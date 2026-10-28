# 鸿蒙互联分阶段实施与验收

更新日期：2026-10-28。主仓仅 UI、通用 IPC 和制品锁；协议实现与测试保留私有仓。

| 阶段 | 状态 | 交付与验收 |
| --- | --- | --- |
| 1 UI | 实施中 | 按已确认原型拆分发现舞台、本机身份、设备卡片、连接引导、发送/来件面板；zh/en、明暗主题、无手机、失败态测试与视觉检查 |
| 2 大文件 | 离线链路已实现，真机待验收 | 审计长度/偏移/内存/超时/临时目录；版本化 IPC、真实进度与取消；10/100 MiB 及更大合成样本双向 hash 验证，按证据声明能力 |
| 3 多文件 | 发送队列已实现，原生批次 Core 离线已验证，IPC/UI 与真机待完成 | 队列、文件级与任务级进度、失败与取消隔离 |
| 4 完整体验 | 持久化记录与通知/目录设置已实现，发布回归待完成 | 系统通知、完整持久化记录、打开路径/重试、设置与发布回归 |

## 当前证据与边界

- 开始时主仓 `fdf5ba03b3061b8d6efd829eb06bb770f9574aa6` 与私有仓工作树均干净。
- 原有真实双向测试只覆盖前一包小文件；最终自广播修复后的包未复验；不得当作本轮结果。
- 起始基线是单个普通非空文件 ≤1 MiB；阶段 2 已扩展至实验单文件 1 GiB。阶段 3 当前支持 1–100 文件发送队列，仍逐项建立核心会话；手机原生批量接收未发布。
- 本轮浏览器拒绝 `file:` 原型地址（URL policy）。已读取 HTML/CSS/JS，原型实际渲染对照仍待完成；不绕过策略。Flutter UI 可通过 Widget 渲染截图独立验证。

## 阶段 1 验收记录

- UI 结构已落地：发现舞台、本机身份、设备卡片、连接指引、最近路径区、共用收发确认面板；无设备/关闭/失败/忙碌态分别呈现。
- `flutter test --no-pub test/features/harmony_share_dashboard_tab_test.dart test/core/nearby_share/`：14 项通过。
- `flutter test --no-pub test/features/harmony_share_visual_test.dart`（带截图与本机字体 dart-define）：2 项通过；Light/Dark 的空态、附近设备和来件截图共 6 张，位于 `/tmp/anydeck-harmony-ui/`，已视觉检查。
- targeted `flutter analyze --no-pub`：无问题。
- 自动测试首次暴露测试宿主缺失 Material zh delegate 及布局宽度收缩问题，均已修复；截图使用 MaterialIcons 字体避免占位方框。
- 待验收：原 HTML 实际渲染对照、运行 App 拖放/主窗口来件与真实双向复验。此批不宣称阶段 1 全部验收完成。

UI 变更不触及投屏、HDC/ADB 或私有协议；接收服务继续由主窗口持有，页面销毁只解除 UI 监听。

## 阶段 2 离线交付记录

- 私有 Core `0.2.0` / IPC `2`：commit `21d8bee605793b6183e4f91233c95028df4942d9`；主仓仅更新通用 IPC、UI 与二进制锁。生产 `send/receive=false` 保持不变。
- 实验最大单文件 1 GiB、最长 30 分钟，实际字节进度与取消已接入。发现窗口与传输期限分离，接收期间不再被 125 秒发现 watchdog 回收；准备期间点击取消也会阻止稍后开始发送。
- 离线加密 DFile 双进程：10 / 100 / 512 MiB / 1 GiB 全部完成，双向进度单调且有最终字节值，SHA-256 一致；最终复验 1 GiB 约 10.20 秒，单进程采样峰值 RSS 183,664 KiB。此速度是 loopback 测试数据，不代表手机 Wi-Fi 速度。
- 私有 Rust 18 unit + 4 integration、Swift 11、Python 43 通过；DFile 基础 5 通过 / 1 可选 LAN 未运行；大文件压力测试 4 个样本均通过。
- 主仓 focused Flutter tests 24 项通过，涵盖 IPC、取消、非法进度、最终事件与百分比区分、大文件接收跨 125 秒和早期取消；安装器 Python tests 3 项通过，包含旧 IPC 拦截。targeted analyze 无问题。
- 用户明确暂不方便真机操作，先完成离线验证。**未完成**新包手机双向大文件、拒绝/手机取消/断网/磁盘满及最终 hash 验收，不宣称完整生态链路或生产兼容性通过。
- 私有制品 SHA-256：`106026e891b971c8c004c37a9b67213fe2a43cc087a688ba7ec37970b623a119`。本轮构建通过 `ANYDECK_SHARE_CORE_ARCHIVE` 使用本地已锁定 zip；私有新 commit 未推送，默认远端拉取需待私有 commit 发布。
- 新包位置：`/tmp/anydeck-harmony-large-offline/Products/AnyDeck.app`。Release 构建成功；`codesign --verify --deep --strict`、包内全部成员 SHA-256、IPC 2 / Core 0.2.0 握手通过。没有启动或停止原有 AnyDeck 实例。

## 后续批次

1. 完成阶段 1 原型实际渲染对照与运行包拖放视觉验收；保留未验收标记。
2. 阶段 3 先做发送多选/队列与任务进度；多文件接收需私有核心支持，不用单文件循环冒充原生批量 offer。
3. 阶段 4 完成持久化记录与通知、路径操作/重试/设置；再补齐真机与发布前回归。

本轮曾因磁盘空间不足中断一轮验证；只清理本轮已停止合成样本的临时目录后，串行重跑压力测试和 Flutter 验证通过。启动/停止竞态新增独立回归用例，避免异步启动迟到后残留接收进程。

最终 Widget 截图已按 IPC 2 / 1 GiB 文案重新导出，视觉布局测试 2 项通过；截图路径仍为 `/tmp/anydeck-harmony-ui/`。

## 阶段 3 第一批：多文件发送队列（2026-10-28）

- 点击设备支持多选，Finder 可一次拖入多个文件到对应头像或唯一设备中央区域；同一选择统一确认后发送，确认页展示数量、总大小与文件摘要。一次最多 100 个文件、单个最大 1 GiB；目录、链接、空文件、超界选择拒绝，重复路径去重。
- `ShareSendSelection` 只读取元数据；队列开始每项前复核文件类型、大小与修改时间。`HarmonyShareSendQueue` 负责串行状态机，UI、拖放样式与队列数据分文件。
- 每项保留 queued / preparing / transferring / succeeded / failed / cancelled，支持取消排队项、取消当前项和取消所有剩余项。单项失败继续下一项；100% 字节仍等待核心最终结果，迟到取消不覆盖核心成功。
- 面板展示总处理数量、成功/失败/取消数量、实际累计字节与各文件进度/失败原因；列表有界滚动，100 项不一次撑开。整个 batch 期间暂停接收，完成后恢复一次；页面退出只移除 UI 监听。
- 自动验证：40 项 focused Flutter tests 通过，targeted analyze 无问题；覆盖严格串行、失败隔离、取消/重复取消、迟到回调、错误进度、队列重用、文件变化与选择边界、整批接收互斥、多文件拖入、目标歧义、zh/en、Light/Dark 和窄窗口。
- 视觉检查：`/tmp/anydeck-harmony-queue-ui/queue-light.png`、`queue-dark.png` 已检查；这是 Widget 离线渲染，不是真机传输截图。新增拖放高亮复用 feature 内薄组件；现有 ADB 上传覆盖层与其 Provider 耦合，不接入鸿蒙互联。
- **范围边界**：当前是多文件发送队列，每个文件仍需要手机确认。私有 IPC 与协议本批未修改，仍拒绝原生多文件来件；不得描述为“原生批量收发已完成”。持续队列添加、速度/剩余时间和完整持久化记录仍需继续。
- 手机操作按用户要求暂缓。新 Release 包 `/tmp/anydeck-harmony-queue-offline/Products/AnyDeck.app` 构建成功；`codesign --verify --deep --strict`、包内成员 SHA-256 与 IPC 2 握手通过。原有 AnyDeck 不启动、不终止。

## 阶段 4 第一批：持久化记录（2026-10-28）

- 独立 SQLite `harmony_share/history.sqlite` 保存方向、设备名快照、地址/端口、文件名/路径/大小、创建与结束时间、已传字节、结果/错误、本机 SHA-256 和 retry_of；不存文件内容或协议资料。所有连接在工作 Isolate 内打开/释放，WAL + 串行写入，进度最多每秒检查点一次，终态立即排队保存。
- 发送 batch 的 queued 记录在开始文件发送前持久化；单项状态分别保存。首次写入期间的取消也会补齐终态。接收保存等待确认、接受、成功、拒绝、取消、确认超时、失败、中断；不依据“有弹窗”猜作超时。停止前排空已到达的核心终态，真实落盘成功优先于迟到的取消/中断。
- 重启将未完成记录标为 interrupted，保留上次已保存字节，不自动重发或自动接收。结束时间在恢复场景为检测中断的时间，不能视为精确崩溃时刻。
- 首页显示最近完整记录；完整列表支持发送/接收筛选、文件名/设备名搜索、时间/id 游标分页、详情复制、打开文件/所在目录、发送失败/取消后的明确重试。重试先确认当前附近设备与文件，生成新任务并保留原记录关联。
- 删除仅删除终态任务记录，并有单独确认；不删除实际文件。旧版只有路径的缓存在“路径快捷列表（旧版兼容）”保留，不补造方向/日期。收到请求时若核心尚未提供文件名，记录明确显示“来件文件摘要”，成功后补齐真实文件名与路径。
- 主窗口来件 presenter 拆分，失效/超时只移除自己的 DialogRoute；不会误关叠加的其他弹窗，销毁后也不再访问失效 context。主仓单文件原生会话资源从服务拆到 `HarmonyShareSender`，类文件均低于 500 行。
- 私有 Core 0.2.1 / IPC 2 提供明确 decision_timeout；commit `13ad17f5ffdc4dadca6e80ba1f3a4a9adb51bd71`，zip SHA-256 `56b5836ec9485f4acdd758b5482a8dcd621ed3b202429c2f074d512b117d0c26`。DFile/认证/Swift 未改变，复用已验证且源码未变的 helper；生产 send/receive 仍 false，私有 commit 尚未推送。
- 验证：主仓 68 项 focused Flutter tests 与 targeted analyze 通过；私有 Rust 19 unit + 4 integration 通过。覆盖 SQLite 回读/搜索/分页/恢复/删除、记录保存竞态、迟到成功、输入关闭与确认超时、真实服务状态映射、弹窗生命周期、zh/en 与 Light/Dark。
- 已视觉检查 `/tmp/anydeck-harmony-history-ui/history-light.png` 与 `record-details-dark.png` 等 Widget 图。详情组件改为独立 Dialog 进行捕获，避免把底层页面截图误当作叠加弹窗。
- 测试包 `/tmp/anydeck-harmony-history-offline/Products/AnyDeck.app` 的 Release 构建、codesign 深度严格校验、包内全部成员 hash 和 Core 0.2.1 / IPC 2 握手均通过。没有启动新包或停止用户原有实例；未进行手机、真实 Finder 点击和重启 App 的人工验收，数据库持久化/恢复由隔离临时库测试验证。
- 仍待：系统通知与点击路由、接收目录/通知设置、本机名称的核心同步、原生多文件来件、发送队列追加与更完整速率展示、真机和发布前回归。长期目标保持未完成。

## 阶段 4 第二批：通知与接收目录（2026-10-28）

- 主窗口通过 `harmonyShareNotificationsProvider` 复用现有 `macNotificationBridgeProvider`，不另建 MethodChannel handler。来件提醒、接收成功/失败/确认超时/中断提醒、发送批次完成汇总已接入；发送结果按成功/失败/取消计数，每个 batch 只通知一次。主动拒绝或取消接收不额外提醒。
- 通知仅含通用摘要与 `{type: harmony_share, targetTab: -4}`，不携带设备名、文件名、本地路径或自动接受动作。点击优先导航 `/harmony-share`，不依赖 ADB/HDC 设备，不打开文件。原有 Swift 桥接继续负责聚焦主窗口与冷启动点击缓存；未更改其他设备/手机消息通知路由。
- 来件通知随确认处理/超时/会话失效撤回；启动清理旧来件提醒，已完成结果保留。后台只检查已有系统权限，`notDetermined/denied/unknown` 不自动申请或重复补发历史；申请入口位于显式设置操作。通知关闭后移除本模块通知，不影响其他模块。
- 通知队列上限 16，结果去重缓存上限 256，异步调用 5 秒超时且不阻断传输。即使原生送达在超时后才完成，也会检查失效状态并撤回；系统返回失败/异常通过设置面板提示。记录事件流仅输出当前会话新记录，旧 SQLite 记录不重放通知。
- 设置位于互联页标题栏：独立通知开关、系统权限状态/申请/打开系统设置/刷新、接收目录选择/恢复 Downloads。目录由 AppSettingsController 校验、可写探测（15 秒上限）、成功保存后更新并沿用跨窗口广播；为保持文件 <500 行，原有两个通知 setter 原逻辑移入同库 mixin。
- 自定义目录在每轮启动接收器时重新解析，仍创建独立子目录；不存在/不可写时明确失败，不悄悄切回 Downloads。设置仅影响之后的接收，不移动旧文件；收发忙碌时目录按钮禁用，选择器返回后再次检查忙碌。探测只写入新建临时目录并立即清理。
- 自动验证：99 项 focused Flutter tests 与 targeted analyze 通过。覆盖既有互联流程、通知去重/撤回/迟到/异常/权限、批次计数、设置持久化/主子窗口广播、目录失效/探测清理、设置写入 false/异常后的缓存重载、zh/en/Light/Dark/窄窗口。Widget 视觉测试 2 项通过，`/tmp/anydeck-harmony-notifications-ui/settings-light.png` 与 `settings-dark.png` 已检查。
- Release 包：`/tmp/anydeck-harmony-notifications-offline/Products/AnyDeck.app`；最终源码 Release 构建、codesign 深度严格校验、全部包内 Core 文件 hash、Core 0.2.1 / IPC 2 握手均通过。未启动新 App、未结束原实例、未弹出真实通知或系统授权、未访问真实接收目录。系统通知横幅/点击唤醒、原生目录选择器和手机链路人工验收仍待进行。
- SharedPreferences 写入失败时重读缓存后向 UI 报错，避免后续接收使用失败写入留下的内存目录值。测试显式声明已有 transitive `shared_preferences_platform_interface` 为 dev dependency，不增加 runtime 依赖；真实磁盘满/存储完全不可读场景仍待回归。
- 本批私有协议、Core 0.2.1 / IPC 2 和制品锁不变。本机名称需与核心同步后开放；原生多文件收发、队列追加/速率、真机与发布前回归仍未完成。

## 阶段 3 第二批：原生批次底座（2026-10-28）

- 私有仓 commit `b729c88` 完成有界 DFile 原生清单底座：单个加密会话发送 1–100 个文件，单项 ≤1 GiB；接收在分配清单内存前校验数量，在实际写盘前检查所有文件元数据与精确总大小，排他预留避免覆盖已有文件/链接或文件系统名称折叠冲突。legacy 单文件入口继续拒绝批次。
- 离线 batch suite 9 项通过，包含 12 个直接写盘边界场景及内存分配/NUL 入口验证；100 文件和 110 MiB 混合 batch 逐文件流式 hash 一致，双方总进度单调且到达真实总大小。普通、中文、空格和换行文件名均实际传输验证。
- 负向验证：错误数量/总大小在写盘前失败且目标目录为空；101 个不同文件、重复名称、链接、空文件、单文件超 1 GiB、清单格式/权限/长度错误在联网前拒绝。既有 DFile 5 通过/1 LAN 跳过，10/100/512 MiB/1 GiB 压力样本全部通过；新一轮 1 GiB 约 7.99 秒、采样单进程峰值 RSS 170576 KiB，仍只代表 loopback。
- 私有 Rust 19 unit + 4 integration 回归通过。复用已准备固定依赖重新编译 CMake；两处修改过的上游编译输入均与固定 commit 原文件应用精确补丁后的内容逐字一致。全量三依赖 clone/prepare 未重新完成，不宣称 fresh machine 构建通过。
- **此批仅完成私有 helper 底座**。Rust 生态批次 offer/用户确认、snapshot 与 staging 发布、IPC/Flutter 的批次任务模型尚未接入，不代表手机原生多文件收发完成。主仓生产/实验能力声明和 Core 0.2.1 / IPC 2 制品锁保持不变，未替换 zip 或测试 App，未操作手机。
- 下一批继续私有 Core 的真实批次状态机与取消/失败验证，再版本化通用 IPC 和 UI；不直接把单文件数量限制改大后宣称完成。

## 阶段 3 第三批：Core 原生批次状态机（2026-10-28）

- 私有仓 commit `83f9aee`：内部 Rust 批次 API 已接入实际认证、一次整批确认、原生批次传输、逐文件元数据/大小/hash 校验与 staging 整目录原子发布。发送先完成全部私有流式 snapshot；任一准备失败不会开始网络发送，准备与校验均检查期限/取消，内存缓冲固定。
- legacy 接收仍只允许单文件，批次入口独立限制 1–100 项、单项 ≤1 GiB、精确总大小；元数据按文件有界输出，禁止仅通过扩大一个数量限制开放批次。接收目标竞争也使用不覆盖的原子目录操作，拒绝/失败/取消不发布半批文件。
- 完整离线数据链：100 文件发送、含 10 MiB 的三文件接收均通过真实认证/确认/绑定/加密传输/逐文件独立源 hash 与目录发布。两方向分别运行“1 GiB + 64 KiB”双文件批次，跨 1 GiB 总量与最终各文件 hash 均通过；完整用例约 16.16/17.93 秒，含 fixture/snapshot/校验，不是手机 Wi-Fi 速度。
- 负向链路：主动拒绝整批后无发布/残留；确认后目标被其他进程创建，原文件保留、接收报告发布冲突并清理 staging。实际数据传输中先观察 progress 与存活 DFile 子进程再 SIGTERM，5 秒内结束，已观察子进程退出，snapshot/staging 清空且无发布目录。
- 验证：32 常规 Rust lib tests + 1 显式 GiB 压力用例（双角色）+ 4 integration 通过；DFile batch 9 通过、legacy 5 通过/1 LAN 跳过；Rust Release 编译通过，无 warning，新增/修改文件均小于 500 行。测试仅用临时目录和 loopback 临时端口。
- **证据边界**：测试专用 Meta 主动端模拟手机行为，不进入 Release；双方生产默认均等待手机发起该步骤，因此不据此宣称 AnyDeck 对 AnyDeck 自动互操作或真实手机兼容。发送 DFile ACK 只说明传输层完成，接收最终发布和远端 hash 仍须分别判断；测试明确覆盖发送 ACK 成功但接收发布失败的场景。
- 本批未变更对外 IPC 2、能力声明、制品锁或 zip，未替换/启动 App、未操作手机。当前 Flutter 仍调用单文件会话；下一批继续版本化批次 IPC、文件级任务/记录/确认/通知和真实进度 UI，再更新锁定制品。
