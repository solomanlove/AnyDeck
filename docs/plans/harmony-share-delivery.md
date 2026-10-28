# 鸿蒙互联分阶段实施与验收

更新日期：2026-10-28。主仓仅 UI、通用 IPC 和制品锁；协议实现与测试保留私有仓。

| 阶段 | 状态 | 交付与验收 |
| --- | --- | --- |
| 1 UI | 实施中 | 按已确认原型拆分发现舞台、本机身份、设备卡片、连接引导、发送/来件面板；zh/en、明暗主题、无手机、失败态测试与视觉检查 |
| 2 大文件 | 离线链路已实现，真机待验收 | 审计长度/偏移/内存/超时/临时目录；版本化 IPC、真实进度与取消；10/100 MiB 及更大合成样本双向 hash 验证，按证据声明能力 |
| 3 多文件 | 原生批次/连续队列与发送速率已接入，真机待验收 | 队列、文件级与任务级进度、失败与取消隔离 |
| 4 完整体验 | 持久化记录/故障重试与通知/目录设置已实现，发布回归待完成 | 系统通知、完整持久化记录、打开路径/重试、设置与发布回归 |

## 当前证据与边界

- 开始时主仓 `fdf5ba03b3061b8d6efd829eb06bb770f9574aa6` 与私有仓工作树均干净。
- 原有真实双向测试只覆盖前一包小文件；最终自广播修复后的包未复验；不得当作本轮结果。
- 起始基线是单个普通非空文件 ≤1 MiB；阶段 2 已扩展至实验单文件 1 GiB。阶段 3 当前支持 1–100 文件原生批次收发 UI，一次选择对应一个核心发送会话；手机兼容性未验收，生产能力仍未发布。
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

## 阶段 3 第四批：IPC 3 与 Flutter 批次解析模型（2026-10-28）

- 私有仓 `468f828` 定义 Core 0.3.0 / IPC 3：新批次命令、实验能力/count/总量声明、版本与实验开关门控；发送使用已确认的 path/bytes，全部 snapshot 后逐文件复核大小，不符时在启动网络前失败。生产 send/receive 保持 false。
- 接收完成按“逐文件结果 + 最终批次摘要”输出，不把 100 个深目录路径集中到一个超长 JSONL。Flutter 独立 `share_batch_contract.dart` 验证 UTF-8 请求长度、数量/大小、重复文件名、目标 IPv4、结果 index/路径归属/hash/大小/精确总量；收齐终态后返回不可变结果，不能仅靠字节 100% 或部分文件事件确认整批成功。
- 验证：Rust 32 常规 lib + 5 integration 与 Release 编译通过；覆盖 IPC 2 拦截、实验门控、坏参数、声明与 snapshot 大小变化在联网前失败。GiB 压力本批显式跳过，前批独立验证结果不冒作本批完整 IPC 成功链路。主仓 nearby_share 58 项测试与 targeted analyze 通过。
- 本批为契约与解析模型准备。主仓运行入口仍用 IPC 2，未切换 Client/Session、收发服务、历史/通知或制品锁；未生成/替换 zip、启动 App、操作手机。下一批接通完整调用与任务状态后，再打包 IPC 3 制品并联调。

## 阶段 3 第五批：Client/Session 与 IPC 3 制品（2026-10-28）

- 主仓 ShareCoreContract 切换 IPC 3，握手严格要求 native_batch、100 文件与精确最大总量声明；旧 IPC 2 明确拒绝。新增 ShareBatchClient 与双向 Session，沿用通用进程资源回收，支持 stdin 请求/确认、严格总量/方向/单调进度、完整终态、不完整/重复/非法事件拦截。
- 原生接收文件事件先有界收集，逐文件及最终摘要齐全才向服务输出完整文件集合；不根据单独 100% 进度确认整批成功。有效发送终态优先于迟到取消，重复取消幂等。启动写管道失败/解析失败回收已启动进程；接收确认只写一次，退出清理 stdin，失败不生成假文件结果。
- 私有仓 `7059e220004229e7f1df347c667bd11a064ccd16` 包含 Core 0.3.0 / IPC 3 arm64 zip；SHA-256 `2c23cab15e578e3d0d3cfe1cd9268d734f7764bbc84149acdfb4a43cc66c8d58`。主仓锁同步，生产 send/receive 仍 false。私有新 commit 未推送，本轮以相同 hash 本地 archive override 构建。
- 实际 IPC 子进程发送联调通过：从 stdin 输入新批次命令，执行真实 Core 认证/传输并返回批次终态，接收各文件 hash 一致；隔离 BLE stub 不访问蓝牙。显式“1 GiB + 64 KiB”真实 IPC 模式也通过（约 15.12 秒完整测试用例，非手机 Wi-Fi 速度）。
- 自动回归：Flutter 115 focused tests 与 targeted analyze 通过；installer 3 tests 通过，包含 IPC 3 拒绝旧制品；私有 Rust 33 常规 lib + 5 integration 通过，另有显式真实 IPC GiB 测试通过。前批双角色 SDK GiB 压力本批未重复。
- 本批新包路径 `/tmp/anydeck-harmony-ipc3-offline/Products/AnyDeck.app`；Release 构建、codesign 深度严格校验、Core 成员 hash、IPC 3 握手与 IPC 2 拦截均通过。未启动新 App、未停止原实例、未操作手机。
- **仍待服务接线**：现有 UI 继续使用 IPC 3 下兼容的逐项单文件队列与接收命令。新批次 API 已可调用，但收发状态、确认、记录/通知与 UI 尚未切换；不能描述为 UI 已支持一次手机确认的原生批次。

## 阶段 3 第六批：原生批次接收与文件记录（2026-10-28）

- 主窗口接收服务切换 `receive_batch_interactive`。来件一次展示整批数量与总大小，接受/拒绝/30 秒超时作用于整批；已配置接收目录、忙碌互斥与 watchdog 沿用原服务。进度仅接受与来件相符的真实总量，逐文件事件与最终摘要完整验证后才更新结果。
- 接收会话停止时同时排空原始流和批次验证流，避免取消竞态吞掉已经校验的最终成功；晚到成功只可修正取消/中断，不覆盖明确拒绝。生产能力继续关闭，UI 保留实验状态。
- SQLite 原地迁移增加 `file_count` / `batch_id`：整批摘要与子文件在同一事务保存；首页只展示摘要，按文件名搜索可找到子文件，详情按需加载至多 100 项。子文件保留独立路径、大小、本机 SHA-256；删除摘要同时删除其文件记录，磁盘文件保留。单文件仍使用原记录形式。
- 批次详情复用记录行、Theme 与双语文案，支持显式打开文件/目录和详情；Theme rebuild 不重复查库。批次目录动作打开发布目录本身，系统结果通知仅发一条数量摘要，不逐文件刷屏。
- 自动验证：128 项 focused Flutter tests、targeted analyze、2 项 Widget 视觉布局测试通过；覆盖真实旧库迁移/回读/搜索/级联删除、服务接受/拒绝/超时/坏终态/取消竞态、通知汇总、480px zh/en 与 Light/Dark。已查看 `/tmp/anydeck-harmony-native-receive-ui/batch-details-light.png` 和 `batch-details-dark.png`，属于 Widget 离线渲染。
- 私有仓测试 commit `e040923` 增加真实接收 IPC 子进程联调：先等 stdin 确认再传输，逐文件结果与完整摘要一致，落盘 hash 与独立源文件一致；隔离 BLE stub，不使用手机。34 常规 Rust lib + 5 integration 通过，最后的独立源 hash 断言用例再次通过。此前 GiB 用例未在本批重复。生产源码和制品未变，主仓锁继续固定 `7059e22` / Core 0.3.0 / IPC 3。
- Release 包继续输出到 `/tmp/anydeck-harmony-native-receive-offline/Products/AnyDeck.app`；最终源码构建、codesign 深度严格验证、5 个 Core 成员 hash、Core 0.3.0 / IPC 3 握手通过。未启动新 App、未停止原实例、未操作手机或系统通知。
- **剩余项**：发送 UI/队列仍为逐文件会话；原生发送批次接线、队列追加/速率、本机名称真实同步、存储故障重试和真机/发布前验收继续推进。不能据此宣称手机原生双向批量验收完成。

## 阶段 3 第七批：原生批次发送接线（2026-10-28）

- `HarmonyShareService` 与 `HarmonyShareSender` 将一次选择映射到一个 `send_batch_experimental` 会话；发送前检查全部文件的类型/大小/修改时间和批次名称冲突，Core 继续执行完整 snapshot 和大小复核。旧串行代码仅保留为兼容调用，正式服务选用原生批次，失败不会自动回退逐项发送。
- 队列新增不可变批次快照。只有总进度，UI 显示整批字节，不将其平均分摊到各文件；100% 字节仍等待有效 `batch_sent` 终态。整批取消幂等，准备/网卡检测/启动管道等待期间取消均保留意图，迟到的有效成功优先于取消，旧批次迟到进度不会污染后续批次。单文件实时进度尚未由 Core 输出。
- 原生队列隐藏逐文件取消；确认页说明整批一次确认及整批失败/取消语义。文件行沿用整批状态；发送完成明确不代表手机落盘 hash 已验证。停止服务现在等待发送清理与记录保存，避免销毁后仍有状态回调。
- 发送记录以一个批次摘要和已知子文件清单在事务内保存，进度检查点最多每秒一次；失败/取消后的子文件字节显示未知，不把默认 0 当作实际进度。单文件批次仍保留原路径和单条记录。详情支持显式重试某个失败子文件，生成新任务并保留原记录关联，不自动重发。
- 147 项 focused Flutter tests 与 targeted analyze 通过，包含整批单会话、100 项/跨 GiB 总量模型、总量与单调性、早期/迟到取消、文件变化/同名拦截、停止排空、SQLite 重开、一次通知、zh/en/Light/Dark/480px。100 项/跨 GiB 是本批状态模型测试，实际 GiB 传输证据沿用前批 Core 联调，本批未重复压力传输。
- Widget 视觉测试 2 项通过，已查看 `/tmp/anydeck-harmony-native-send-ui/native-send-queue-light.png` 与 `native-send-queue-dark.png`。这是合成状态离线渲染，不是运行中 App 或手机截图。
- Release 包 `/tmp/anydeck-harmony-native-send-offline/Products/AnyDeck.app` 构建成功；codesign 深度严格验证、zip 与锁定 hash、5 个 Core 成员 hash、Core 0.3.0 / IPC 3 握手通过。私有协议、zip、主仓锁未变，继续固定 `7059e22`，生产 send/receive=false；未启动 App、未停止用户实例、未操作手机/通知/Finder，未 push。
- 仍待：持续队列追加与批次之间失败隔离、速度/剩余时间与单文件真实进度、本机名称同步、持久化失败的可靠重试，以及原 HTML/真实 App/手机双向和发布前验收。完整目标保持未完成。

## 阶段 4 第三批：持久化故障恢复（2026-10-28）

- 修复原串行写入在失败后遗失快照、后续无关写入成功清掉错误的问题。`ShareHistoryWriter` 按任务保留最新元数据，合并同一任务的更新；一个写入事务失败时保留整批摘要和子文件，而非仅重试最后一条记录。进行中的事务使用 revision 校验，旧提交不会删除较新的终态。
- 缓冲预算为 1024 个记录槽位，活跃批次预留完整摘要/子文件容量，成功终态落盘后释放。容量不足在更新缓存之前报错：新发送任务在启动 Core 前失败，新来件在用户接受之前拒绝；已预留任务可继续保存终态，不通过丢弃旧记录腾空间。缓冲仅包含元数据，不读取文件内容。
- 写入严格串行，失败后按 1/2/5/10/30 秒退避，后续最多每 30 秒一次；只有一个重试 Timer。新进度在退避期间合并，不产生密集数据库请求。显式重试/结束时 flush 尝试补写，dispose 取消重试且不再通知已销毁页面。
- 首页与完整记录弹窗共用存储错误组件，双语提示待保存记录仅保留在本次运行；重试防重复，关闭弹窗后返回安全。已出现“记录有更新”后仍能刷新后续存储错误。已知容量错误统一本地化，不把内部错误码直接显示给用户。重试只补写/重读元数据，不重发文件、重放接收成功或系统通知。
- 写入未恢复时，查询/文件清单不会以旧数据或空清单冒充完整结果；首页仍展示已知缓存。存储永久不可用时无法保证退出/崩溃后的未保存记录，因此 UI 明确提示恢复并重试；不宣称内存缓冲等同持久化。
- 验证：166 项 focused Flutter tests 与 targeted analyze 通过。包含实际 SQLite trigger 在子文件插入时中断、整批回滚、恢复后全部补写；路径被普通文件阻断后的重新打开；自动/手动重试、在途更新、预留容量、发送/接收门控、恢复不重放成功事件、删除不复活、zh/en/Light/Dark/480px 与弹窗销毁。SQLite 注入错误和临时无效路径不等于真实系统磁盘满实测，未填满磁盘或修改用户目录权限。
- Widget 视觉测试 2 项通过，已检查 `/tmp/anydeck-harmony-storage-ui/storage-warning-light.png` 与 `storage-warning-dark.png`，为离线合成组件渲染。
- Release 包 `/tmp/anydeck-harmony-storage-offline/Products/AnyDeck.app`：最终源码构建、codesign 深度严格验证、锁定 zip/hash、5 个 Core 成员 hash 和 Core 0.3.0 / IPC 3 握手通过。私有源码/制品/主仓锁未改，生产 send/receive=false；未启动 App、操作手机/系统通知/Finder，未 push。
- 仍待持续队列追加、速度/剩余时间与文件级真实进度、本机名称真实同步、原 HTML/运行 App/手机双向与发布前验收。目标保持未完成。

## 阶段 3 第八批：连续批次追加与发送速率（2026-10-28）

- `HarmonyShareOutbox` 在既有单批原生传输器外调度，活动批次与待发批次合计最多 8 批，每批仍为 1–100 文件、单文件 ≤1 GiB。活动批次内容不变，新选择/拖放经过独立确认后加入下一批；每批开始时再次校验文件和网卡。前批失败后继续后批，不自动重试失败批次。
- 排队时分配稳定 ID 并提交 queued 摘要/子文件记录，激活时 `runPrepared` 沿用同一 ID，不生成第二套记录。存储故障沿用前批有界缓冲/门控策略，不将内存接受排队误称为已持久化。取消待发批次不会启动 Core；初次保存期间取消会在记录建立后补写终态。
- 原生会话始终串行，整段队列只暂停/恢复接收各一次；停止服务取消当前和待发并等待清理。修复暂停接收时迟到 session_started 清掉发送忙碌态、提前重启接收器的竞态；发送操作存在时不从 stopWindow 自动重启接收。停止排空后再次撤销迟到来件创建的 watchdog，避免它在后续长队列中误触发取消。发送编排抽到同库扩展，服务公开 API 保留。
- UI 可在发送期间继续选择或拖放，确认弹窗在入队后释放门控。队列卡片展示待发项和累计结果；当前批次单独展示文件/进度。待发取消、取消当前批次、取消所有剩余批次语义独立；当前取消后后批继续，全部取消后拒绝追加。已完成展示可精简，但累计结果不会丢失；完整记录仍在 SQLite，重启恢复中断状态，不自动重发。
- 原生连续队列只在整个调度周期结束时发一条结果通知，汇总成功/失败/取消文件数；中间批次结束不提前通知。通知 ID 和计数在周期结束时捕获，保持既有隐私 payload 与权限策略；兼容单批调用保留原汇总路径。
- 发送速率/ETA 使用单调时钟与近 5 秒真实字节样本，采样合并间隔约 250 ms、样本上限 32。单样本、初始不足 500 ms、零增量、停顿超过 3 秒、取消或结束时不展示估算。仅活动期间以 1 Hz 刷新过期状态，估算失效后停止 Timer，新进度再启动；结束/dispose 回收。100% 字节仍等待最终批次结果，不虚构单文件进度、整队列 ETA 或手机落盘 hash 验证。
- 验证：187 项 focused Flutter tests 与 targeted analyze 通过。包括 FIFO/容量/取消/保存竞态、完成项精简后累计结果、真实临时 SQLite 排队与终态回读、文件变化在 Core 调用前失败、迟到来件、一次接收恢复、一次周期通知、速率高频/时钟/过期与 Timer 释放、zh/en/Light/Dark/480px。服务测试注入 Client；没有把它描述为真实手机或本批新 Core 传输压力验证。
- Widget 视觉测试 2 项通过，已查看 `/tmp/anydeck-harmony-outbox-ui/outbox-rate-light.png` 与 `outbox-rate-dark.png`。图中速率/时间为合成 fixture，用于布局检查，不是实际吞吐结果。
- Release 包 `/tmp/anydeck-harmony-outbox-offline/Products/AnyDeck.app` 构建成功；codesign 深度严格校验、锁定 zip 与 5 个 Core 成员 hash、Core 0.3.0 / IPC 3 握手通过。私有源码/zip/主仓锁未变，生产 send/receive=false。未启动 App、未操作手机/系统通知/Finder、未 push。
- 剩余：本机名称真实同步、Core 文件级真实进度、原 HTML/运行 App/手机大文件双向和发布前回归。完整目标继续保持未完成。

## 本次大文件与临时产物清理（2026-10-28）

- 按用户新增的低存储约束，删除本任务生成的 12 份 `/tmp` 隔离测试 App 目录和私有 Core 的已忽略 `core/target` 编译缓存，共 13 个目录，删除前统计分配空间约 2189.3 MiB（约 2.1 GiB）。清理后 `df` 可用空间约 3.5 GiB；其他工作流仍可能改变可用空间。
- 最后一份 `/tmp/anydeck-harmony-outbox-offline/Products/AnyDeck.app` 在最终源码构建、严格签名/hash/IPC 验证完成后删除。此前章节的隔离 App 路径是历史验证记录，当前不再保留实体包；需要时通过锁定 zip 和构建脚本重建。
- 当前 `/tmp` 与系统临时目录未发现本任务残留的 ≥64 MiB 合成传输样本。未删除其他来源的 ADB 日志、媒体缓存、在用 App、共享 Flutter 构建目录、用户源码或锁定 zip。私有仓无关 `.DS_Store` 也保持不动。
- 小型验证日志、Widget 截图和 `/tmp/anydeck-harmony-cleanup-manifest.json` 清理清单保留；最终包检查摘要为 `/tmp/harmony-outbox-package-verify.log`。后续验证避免重复生成 GiB 样本，临时大文件/隔离 App 在验证后继续清理。
