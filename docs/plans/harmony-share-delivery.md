# 鸿蒙互联分阶段实施与验收

更新日期：2026-10-28。主仓仅 UI、通用 IPC 和制品锁；协议实现与测试保留私有仓。

| 阶段 | 状态 | 交付与验收 |
| --- | --- | --- |
| 1 UI | 主要 UI 已实现，运行包待验收 | 发现舞台、扫描动画、本机身份/改名、设备卡片、连接引导、发送/来件与异常提示；zh/en、明暗主题、窄窗口与 Widget 视觉检查 |
| 2 大文件 | 离线链路已实现，真机待验收 | 审计长度/偏移/内存/超时/临时目录；版本化 IPC、真实进度与取消；10/100 MiB 及更大合成样本双向 hash 验证，按证据声明能力 |
| 3 多文件 | 原生批次/连续队列、文件级进度与发送速率已接入，真机待验收 | 队列、文件级与任务级进度、失败与取消隔离 |
| 4 完整体验 | 持久化记录/故障重试、通知/目录/名称设置已实现，发布回归待完成 | 系统通知、完整持久化记录、打开路径/重试、设置与发布回归 |

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

## 阶段 4 第四批：本机名称 Core 准备（2026-10-28）

- 私有仓 commit `5bfaf66`，Core 源码版本 0.3.1 / IPC 3：发现与原生批次命令接受可选 local_name，缺省 AnyDeck；最多 24 UTF-8 字节，空值/非字符串、首尾空格、控制与分隔字符拒绝，不静默截断。hello 显式声明 batch_local_name/max_local_name_bytes，legacy 单文件命令显式带名称时拒绝，避免悄悄忽略设置。
- 名称绑定当前会话，贯通发现广播/响应、发送 offer、双向 meta 与 Swift helper argv/广播字典；不使用可变全局环境，不改变身份摘要或传输数据链。协议实现、wire 测试及 Swift 参数处理均保留私有仓。
- 验证：36 项 Rust lib（含显式 SDK/接收 IPC 用例，排除 GiB 用例）、6 integration 与 12 Swift tests 通过；Rust Release 编译和 0.3.1 hello 通过。发送端加密 offer/meta 在 loopback 核对自定义名；真实接收 IPC 核对 helper --name 与接收 meta 的名称、最终文件 hash。Swift 测试只构造字典/解析参数，不启动 manager 或真实广播。
- 本批是 Core 准备，未生成新 zip、未改主仓锁与 App UI，主仓仍使用7059e22的 Core 0.3.0 / IPC 3。设置入口、跨窗口保存/同步、Dart 同边界校验、能力门控、新制品/锁与 App 验证留待下一批；不能描述为运行 App 已可改名。实际空口名称与手机展示仍待真机。
- 低存储约束：测试关闭 debug info/incremental，使用小型合成文件，不重跑 GiB 压力；测试目录自动回收后删除本轮 core/target 与 Swift .build 缓存约528.5 MiB。源码/旧锁定 zip/小型日志保留，当前可用空间约2.3 GiB，其他工作流可继续影响该值。
- 本批未运行主 App、未停止用户原实例、未操作手机/系统权限，未 push。主仓仅追加现有阶段计划和已索引知识库内容，没有纳入其他导航/控制台/模拟器工作区改动。

## 阶段 4 第五批：本机名称设置与制品接线（2026-10-28）

- 设置面板新增本机名称、实时 UTF-8 字节计数、保存与恢复 AnyDeck；中文/emoji 按真实字节校验，不静默 trim/截断。共享 ShareLocalName 与 Core 的 24 bytes/控制与特殊空白边界一致，非法持久化值明确失败。身份栏显示服务实际读取的名称。
- AppSettings/copyWith/持久化加载接入名称。名称修改统一由主窗口处理：子窗口先请求主窗口，主窗口在收发忙碌时拒绝；空闲保存预留配置边界，停止空闲接收器，成功后以新名称恢复。磁盘写入 false/异常重读缓存并保留旧值，不广播假成功；子窗口收到广播重读最新落盘值，迟到旧广播不覆盖较新名称。
- 原生批次收发与发现 IPC 显式传 local_name，每个新会话读取一次且会话内固定。保存期间新发送被拒绝、接收不启动，停止期间迟到的未确认会话事件不穿过配置边界。旧单文件入口没有伪装为支持名称。握手要求 batch_local_name=true/max_local_name_bytes=24，旧制品不会忽略设置后继续执行。
- 私有制品 commit `c5177809fda428b1847c852472710b3bfed4ec00`，Core 0.3.1 / IPC 3，zip SHA-256 `08296ff0cdaadec21758499ac860085366530fd6bd8a30085210d2de237485e4`；主仓锁已更新。实际制品五个成员签名/hash、hello 与三个命令非法名称前置拒绝通过。生产 send/receive=false，私有实现没有进入主仓，未 push；构建使用本地 archive override。
- 197 项 focused Flutter tests、targeted analyze、3 项安装器测试通过。新增覆盖名称中英文/emoji/特殊字符/字节边界、双向 IPC 字段、保存失败/并发写入/收发互斥、主子窗口单写入与迟到广播。额外 2 项 Widget 渲染测试导出 `/tmp/anydeck-harmony-name-ui/`，明暗设置面板已视觉检查；截图来自离线 Widget，非运行 App 或手机。
- Release 构建成功；包内 Core 0.3.1 / IPC 3、全部成员 hash、zip/commit 对齐和 codesign --verify --deep --strict 通过，摘要 `/tmp/anydeck-harmony-name-package-verify.log`。验证后删除 `/tmp/anydeck-harmony-name-offline` 与本轮私有 core/target、Swift .build，合计约234.6 MiB；未保留新增大样本或独立 App，清理清单已追加。磁盘短暂降至112 MiB，清理后观察约1.4 GiB，可用值仍随其他工作流变化。
- 手机继续按用户要求暂缓。本轮没有启动/停止用户 App、操作手机/BLE/系统权限；未重跑 GiB 压力。尚待 Core 文件级真实进度、原 HTML 渲染对照、运行 App 交互/真实系统通知/Finder、手机大文件双向与发布前验收，完整目标保持未完成。

## 扫描动画与逐文件进度 Core 准备（2026-10-28）

- 根据新增要求接入扫描动画：HarmonyShareService.scanning 仅在真实发现窗口存活、空闲且无错误时为 true；发送/接收/名称保存/关闭不显示假扫描。3秒双波纹使用 AnimationController + CustomPainter(repaint) + RepaintBoundary，不重建设备卡片，不新增 Timer；禁用动画、无障碍导航、TickerMode 与页面销毁时停止。Dashboard 仅选中互联页时创建页面，离页销毁 Ticker。
- 波纹圆心绑定中央投递区，修复有界布局拉高舞台、设备卡片换行后圆心偏移的问题。Theme 提供颜色，无新增硬编码文案；保留原发送/拖放功能。扫描 UI/样式与服务判定分文件，本机名称编辑及跨窗口安全保存保持已实现状态。
- 203项 focused Flutter tests、targeted analyze通过；新增图像帧变化、前景不重建、停止/减少动态效果/无障碍/TickerMode/销毁回收与空设备/三设备换行几何用例。另2项 Widget导出测试通过，`/tmp/anydeck-harmony-scan-ui/scanning[-next]-{light,dark}.png` 已检查，属于离线渲染，不是运行App或手机证据。
- 私有原生底座60810f0：完整加密帧写入socket后计发送明文字节，实际文件块写入后计接收字节；按文件/块去重，支持乱序/重传/并发，bitmap合计最多16 MiB，字节完成即释放，缺失遥测不推算。18项原生回归执行，17通过、1可选LAN跳过，含小文件/100文件双向hash、ASan/UBSan与legacy AES/UDP回归。
- 私有Core准备6ca9ade：Core源码0.3.2/IPC3声明file_progress，发送按snapshot文件大小、接收按完整清单严格校验，整批总量改用观察到的文件IO进度之和；100%字节仍等待完整终态。40项全库lib回归（排除GiB压力）、6 integration及4项文件进度专项通过，含真实双向IPC文件进度/hash、legacy不新增事件与100 GiB纯算术边界；Release/hello通过。未生成0.3.2新zip，Flutter逐文件模型/展示/历史检查点及新制品仍需接线。
- 本批App继续锁定c517780的Core0.3.1。最终UI源码Release构建、包整体/5个原生成员严格签名、manifest/hash/锁定commit中的zip/hello验证通过，摘要`/tmp/anydeck-harmony-scan-package-verify.log`。没有把准备阶段Core0.3.2放进尚未适配新事件的App；生产send/receive=false。
- 按低存储要求删除本轮Rust编译缓存、两份新增依赖clone与隔离App约363.1 MiB，清单已追加；小型样本与sanitizer工具自动回收，保留已有约16 MiB DFile底座、锁定zip与小型日志截图。磁盘当前观察约9.6 GiB可用，其他工作流也会影响该值。未启动/停止用户App、操作手机或真实BLE，未push；手机大文件双向/运行App/原HTML/真实通知和发布验收仍未完成。

## 阶段 3/4：逐文件进度、历史检查点与 Core 0.3.2 制品（2026-10-28）

- ShareCoreFileProgress/ShareFileProgressLedger 作为通用IPC模型，逐文件检查方向、索引、声明大小、单调性和整批边界；发送精确匹配文件快照，接收逐项学习大小并与最终文件结果核对。未知遥测不分摊、不显示假0%，100%仍等待整批最终事件；坏事件停止会话并回收进程。
- 发送队列同时持有独立文件与整批字节，失败/取消保留最后观察值，旧批次回调与取消后的回调不污染新任务。服务不把文件进度误当整批进度；接收只在明确接受后展示，停止/新会话清空。接收面板按需构建有界文件列表，用稳定序号显示尚未返回名称的文件，文件名只在完整结果后补齐。
- SQLite原地增加progress_known/file_index。发送/接收文件进度沿用每秒检查点、整批事务、容量预留和失败重试；部分接收的失败/中断也保存已知字节/序号，未发布的文件没有虚构路径。最终成功原子补齐完整清单；旧记录不推测新字段。详情区分未知和真实字节，部分清单有明确说明；无路径记录隐藏“打开文件/目录”操作。
- 主仓锁切换私有20893ba4307af53bfeec8851fff4d10f9a59c68a的Core0.3.2/IPC3，SHA-256 `f356fda56a569bdd9418b449bc18b57ceaf87747d8a0780253dd7fc0ceb64ea2`；hello必须声明file_progress，旧制品不会被误用。私有实现/协议资料未进入主仓，生产send/receive=false，未push，构建使用本地archive override。
- 227项focused Flutter tests、targeted analyze、3 installer tests通过；新增IPC坏进度/接受门控/最终大小、服务→队列→SQLite成功失败取消、迁移/真实SQLite事务回滚重试、100 GiB纯算术边界及zh/en/明暗/480px交互用例。额外2项Widget导出通过，`/tmp/anydeck-harmony-file-progress-ui/file-progress-{light,dark}.png` 已视觉检查，属于合成fixture而非手机或运行App截图。
- 实际签名制品小文件双向IPC及legacy旧事件集三项通过；私有72f5163补充1 GiB+64 KiB的签名制品真实发送/接收，逐文件中途进度与精确终值、数量/总量/完整终态和独立源hash通过。最终两方向用例约12.73/12.32秒，均为loopback/BLE stub/模拟Meta证据，不代表手机Wi-Fi速度或兼容性；小文件接收模式也复验通过。
- GiB回归前要求至少6 GiB余量，两方向串行，TMPDIR限定本轮独立目录。每轮结束断言样本目录为空，finally删除根目录；中途进度断言补强后双向复验也按同样策略清理，未保留GiB源文件/snapshot/接收结果。
- 最终源码Release构建与严格签名、5成员hash、锁定commit内zip和Core0.3.2 hello通过，摘要`/tmp/anydeck-harmony-file-progress-package-verify.log`。已删除本轮Rust/Swift缓存与隔离App，含最终菜单保护重建后再次删除的App，累计清理分配空间约467 MiB；清理清单保留。已有小型DFile底座、源码、锁定zip、日志/截图保留，共享Flutter构建和无关.DS_Store未动。
- 本机名称编辑、扫描动画、连续队列、通知与历史故障恢复回归通过；完整目标仍待原HTML渲染对照、用户允许后的运行App/真实系统通知/Finder，以及手机大文件双向/拒绝/取消/断网/真实存储异常与发布前人工验收。手机按用户要求继续暂缓，没有启动/停止原有App或操作真实BLE。


## 离线异常提示审查与当前验收边界（2026-10-28）

- 审查发现普通失败流程会直接展示 Bad state/Core 错误码。新增共享错误说明 helper，识别公开 IPC 错误信封与明确的异常消息，覆盖组件缺失/不兼容、无 IPv4 网络、接收目录失效、源文件变化、无法连接手机、拒绝、超时、空间不足和接收校验失败。中英文均提供处理建议；未知错误使用通用说明，不按路径或任意子串推断原因。
- 原始错误仍保留在服务与持久化记录中。发现页、文件记录及批次详情增加用户主动打开的“技术详情”，可本地选择/复制；批次摘要也展示失败说明。发现页按钮绑定本帧错误快照，服务在下一帧前清除错误也不触发 null 异常。未修改私有传输实现、记录状态机、窗口通信或投屏流程。
- 235 项 focused Flutter tests、targeted analyze 和 3 项 installer tests 通过。新增 8 项覆盖真实异常字符串、收发错误、未知/带路径/多行/方向不符的信封及 zh/en × Light/Dark × 480px 的发现页、文件/批次详情操作；拒绝/超时终态保护与取消后的成功优先规则沿用既有回归。
- 视觉 fixture 将 RepaintBoundary 放在 MaterialApp 外层，实际截取 Navigator overlay，避免把底层页面误认成技术详情截图。最终错误交互与带字体的视觉用例共 10 项复验通过；`/tmp/anydeck-harmony-error-ui/error-message-{light,dark}.png` 和 `error-details-{light,dark}.png` 已检查。这些是离线 Widget 截图，非运行 App、真实系统通知或手机证据。
- 最终源码 Release 构建、deep/strict 签名、5 个 Core 成员 hash/签名、锁定 commit 的 zip hash 与 Core 0.3.2 / IPC 3 hello 通过。锁仍为 20893ba / SHA-256 f356fda56a569bdd9418b449bc18b57ceaf87747d8a0780253dd7fc0ceb64ea2，生产 send/receive=false；摘要 `/tmp/anydeck-harmony-error-package-verify.log`。本轮仅执行 hello，不启动真实发现/广播/传输。
- 验证后删除 `/tmp/anydeck-harmony-error-offline` 临时 App，回收约 97.0 MiB 分配空间，清理清单已追加。未新建大样本；此前两个 GiB 样本根目录及私有 Rust/Swift 缓存均确认不存在。保留小型日志/截图、锁定 zip 与已有小型 DFile 底座，共享 Flutter 构建与无关文件未动。

| 需求 | 当前可证明的结果 | 仍待完成的验收 |
| --- | --- | --- |
| 发现 UI、扫描动画、本机名称 | Widget 明暗/双语/窄窗口、动画生命周期与主窗口单写入同步通过 | 原 HTML 实际渲染对照、运行 App 的发现/拖放/改名与手机名称展示 |
| 大文件双向 | 上一阶段实际签名制品 1 GiB + 64 KiB 双向 loopback、真实中途进度与源 hash 通过 | 手机同 Wi-Fi 大文件、拒绝/取消/断网、真实存储异常及端到端文件核对 |
| 多文件/连续队列 | 原生批次 1–100 文件、最多 8 批、文件与整批进度、取消/重试和失败隔离的离线回归通过 | 手机多文件完整交互、各失败操作与真实进度核对 |
| 系统通知与持久化记录 | 通知调用/权限与记录 SQLite 迁移、事务、重启恢复、存储故障重试通过 | 真实系统通知到达/点击、Finder 路径操作与运行 App 回归 |
| 清理与分批提交 | 合成大文件和临时 App 已清理，各阶段独立本地 commit | 无需为本轮提示修改重跑 GiB 压力；新验证仍须及时清理 |

手机继续按用户要求暂缓，未启动/停止原 App、操作手机或系统权限，未 push。早期改版方案的 Finder 共享扩展、安全作用域书签、更多机型、x86_64、Developer ID 与公证仍有实施/验收待办；Finder 拖放不等同共享扩展，不能据此宣称方案 B/C 或完整目标已完成。


## 通知权限故障保真（2026-10-28）

- 实际 MacNotificationBridge 在权限 MethodChannel 异常或空响应时原先返回 notDetermined，导致互传设置误显示“尚未申请”，还可能进入不必要的授权分支。现仅透传 authorized/provisional/denied/notDetermined，异常、空值、畸形类型及未知状态统一返回 unknown；既有设备通知和消息转发仍复用同一个桥接。
- HarmonyShareNotifications 对权限查询失败设置 deliveryFailed，沿用现有双语失败提示；明确拒绝或尚未申请不误报桥接故障。每个异步边界仍先复核停用/销毁/来件有效性；查询或投递挂起期间失效后的超时、迟到失败不覆盖当前健康状态，迟到成功仍撤回。不后台申请权限、不改变接收决策，后续成功通知清除失败状态。
- 新增实际 Dart MethodChannel + 通知协调器组合回归，覆盖通道异常/空值/畸形响应、合法状态、恢复、停用与销毁后的迟到结果；设置 Widget 补充 zh/en × Light/Dark × 480px 的 unknown 提示、系统设置/刷新入口且不自动触发授权。259 项最终相关功能回归及 targeted analyze 全部通过，日志 `/tmp/anydeck-harmony-permission-{focused,regression,analyze}.log`。
- 原生通知撤回代码本批未修改。核对本机 macOS SDK 的 UNUserNotificationCenter.h 后确认即时通知（trigger=nil）无需按定时请求清理 pending；未把这个最初怀疑项当作已证实缺陷，也未增加仅为测试而重构的原生清理抽象。
- 本批未生成传输样本，未启动/停止 App、执行真实设备发现/传输、投递系统通知或操作手机/系统权限，未 push。手机、运行 App、真实通知/Finder 及其他人工验收边界仍见上一节需求表，完整目标保持未完成。
- 最终 Release 构建、deep/strict 签名、5 个 Core 成员 hash/签名、锁定 commit 的 zip hash 和 Core 0.3.2 / IPC 3 hello 通过。两处生产源码的构建前后 SHA-256 一致，摘要 `/tmp/anydeck-harmony-permission-package-verify.log`；仅执行 hello，不启动真实发现或广播，锁与生产能力声明保持不变。
- 本阶段三次隔离 App 删除事件均已写入清理清单，累计约 290.9 MiB 分配空间；最终 `/tmp/anydeck-harmony-permission-offline` 已删除。之前 GiB 根目录及私有 Rust/Swift 缓存仍不存在，未生成新传输样本，保留共享 Flutter 构建、锁定 zip 与小型日志。

## 真机首轮与接收窗口状态修复（2026-10-28）

- 用户已允许独立测试 App 和 nova 12 Ultra 验收，取代之前暂缓真机的安排。隔离 bundle ID、设置与接收目录，使用新建合成文件；用户原有 Debug App 保持运行。实际设置页保存 AnyDeck-Test，手机端已由用户确认可以看到该名称。
- 64 KiB、1 MiB 分别发送成功；64 KiB 经手机回传，实际接收文件大小与源 SHA-256 一致。这只证明该小文件往返。原生两文件批次先出现连接失败，随后一个已建立 TCP 的批次长时间保持 0 B，已主动取消并确认 Core 与 staging 清理；另一批次返回 phone_rejected，尚未得到用户是否主动拒绝的确认。多文件和大文件不能据此判定通过。
- 运行界面复现发送准备/刷新时，主动关闭旧接收器的末尾错误污染当前全局提示。现仅在主动排空期间抑制全局错误展示，历史终态及迟到成功处理保留，活动接收器的 IPC/Stream 失败仍可见。自然结束发现窗口和重新启用服务时清理旧设备，下一窗口必须重新发现；发送暂停接收不清空当前目标。
- 新增 6 项生命周期回归，修复前明确复现两种关闭错误和两种旧设备残留；最终 265 项相关 Flutter tests、targeted analyze、Release 构建与 deep/strict 签名通过。日志 `/tmp/anydeck-harmony-{shutdown-after,real-regression,real-analyze,real-refresh-package-verify}.log`。私有 Core 制品与锁保持 0.3.2 / 20893ba，不因这些 UI 修复修改协议或生产能力声明。
- 真实通知授权尚未完成：工具拒绝访问系统授权代理，已交由用户手动操作，没有绕过。退出独立测试 App 时发现接收 Core 遗留，已按验证过的独立路径/PID停止本次进程；原有 App 未停止。退出清理修复、更新包真机复验、手机多文件/GiB 双向与通知/Finder 操作仍待继续。

## Core 0.3.3 数量一致性与退出清理（2026-10-28）

- 用户随后确认：此前两文件请求未显示，且没有主动拒绝；已手动允许测试 App 通知。通知状态仍需 App 实际重查，不将用户授权回复当成通知送达证据。
- 私有仓已修正批次摘要的数量一致性，并增加宿主退出后的资源回收。主仓仅更新制品锁，不纳入协议实现或诊断数据。锁固定 05d7e41911eff34509d17aa9dd7e7317c16b80fe，Core 0.3.3 / IPC 3，zip SHA-256 为 2350f8979dc49a4c0aae5d52be6b012164d887cf8ede3d7a0565aab24638460d；生产 send/receive 仍 false。
- 私有 40 项非 GiB 原生库/真实签名 IPC 回归、8 项 integration 通过，含两项签名制品父进程退出测试；摘要与退出回归均有修复前失败证据。本批未重跑 GiB 样本。主仓 3 项 installer tests 通过，上一批最终 Flutter 源码的 265 项回归不受制品锁更新影响。
- 以已构建的最终 Flutter Release 包替换独立 App 中的锁定 Core，保留隔离设置与历史；重新签名后 deep/strict、5 成员 hash/签名与 0.3.3 hello 全部通过。小型摘要 `/tmp/anydeck-harmony-real-20261028/core033-package-verify.json`。开始更新包运行复验，实际手机批次、系统通知与 App 退出尚不能仅依据离线测试判定通过。

## 首轮大文件与连续队列实测、LAN 边界（2026-10-29）

- Core 0.3.3 的独立 Release App 实际向 nova 12 Ultra 发送 100 MiB + 1 GiB 两文件批次，传输期间追加 64 KiB 后续批次，最终三文件成功，用户确认全部收到。界面显示真实逐文件字节、速率/剩余时间；SQLite 回读得到 50 个 1 GiB 中途检查点。大文件发送记录 send-1793200720395426-6，追加记录 send-1793200816512827-9；只证明发送回调和用户收件，回传 hash 仍待核对。
- 32/48 KiB 两文件发送经手机确认成功，隔离即时确认的诊断接收回传后大小与源 SHA-256 一致。App 等待接收确认后仍复现失败，不能以诊断接收成功替代完整 App 双向验收。用户随后连上 HDC/投屏并授权自主测试；仅操作当前 nova 和合成文件，原有 App、投屏始终保留。
- 等待期间手机转入直连模式，数据连接使用 P2P 地址，在 LAN 数据端口持续 SYN_SENT，没有到达 Core。当前实验能力只覆盖 LAN；没有切换 Mac 网络或宣称直连已支持。无效试验已撤回，协议实现/原始诊断仍保留私有边界。现在对该模式及时显示中英文明确提示，避免未知错误或继续等待；该限制仍是未完成验收项。
- Core 0.3.4 同时将空闲发现到期正确报告为 deadline，避免周期性误报文件输入错误。主仓锁固定 ca77499fc94fcaf449b399ac506ddf734c520137，zip SHA-256 ba685fcccbc8c9666f13bbfd063c1e90e3fc1c98b320773a1cda3542eced27fb，IPC3，生产 send/receive=false。41 项非 GiB 原生库/签名 IPC、9 项 integration、265 项相关 Flutter tests、targeted analyze 与 3 项 installer tests 通过。
- 本批最终 Flutter 源码重新构建 Release，更新独立 App 后 deep/strict、5 成员 hash/签名与 0.3.4 hello 全部通过，摘要 core034-package-verify.json。0.3.3 实际 App 退出时 Core/BLE helper 已确认全部自动回收，原 App PID90081 与投屏继续运行。大文件 LAN 回传、当前包结果展示及通知/Finder 继续验收；大样本仍复用同一份，结束后清理。


## 自主回传复验与当前失败证据（2026-10-29）

- 用户授权通过现有 nova 12 Ultra 投屏自主操作。Core0.3.4 独立 App 实际接收 100 MiB+1 GiB 请求并确认，进入文件数据阶段；记录 receive-1793205453345513-1 最后保存 1,073,290,790 / 1,178,599,424 bytes，首文件子记录相同进度，随后 receive_failed: dfile_failed。本轮观察到 40 组 SQLite 中途/终态采样；未发布完整文件，没有可用于双向验收的落盘 SHA-256，不能按接近 1 GiB 判定成功。
- 源码已在接受来件后将传输期限设为 1800 秒；本轮不能仅按约 112 秒用时归因为两分钟接收期限。失败原因尚未确定，不修改生产能力或错误记录。复用既有合成文件，没有重新生成 GiB 样本。
- 两次自主 100 MiB 单文件复验、一次用户重置华为分享后手动发起的对照均在协商阶段报告 unsupported_network_mode，字节为 0；其中一轮在手机 Wi-Fi 重连后，已通过 HDC 只读查询确认 SSID 恢复 jie_5G。及时确认和重试均不能保证绕开手机直连模式。单独诊断接收器期间未收到来件，仅产生发现到期/准备失败，不能计为 DFile 传输兼容性结果；相关诊断进程已停止。
- 期间 Mac 锁定导致投屏停帧与自动化不可用；用户手动解锁后恢复原 App 的投屏并继续，未停止原实例。实际记录导出在隔离目录 history-export.json、检查点为 receive-core034-checkpoints.jsonl。大文件回传仍未通过，保留两类实际失败，不假造成功或 hash。
- 修正中英文直连提示，删除“重新发起并及时确认”可作为恢复方法的暗示，明确重试仍可能遇到相同限制。新增该错误在 zh/en × Light/Dark × 480px 的提示、原始诊断隔离与点击回归；本次 12 项错误相关 tests、targeted analyze 和 diff 检查通过。只修改文案与测试，没有更改 Core、生产开关或系统权限策略；未重建/重启原 App。
- 实际 App 的记录详情正确展示此前接收的 64 KiB 文件路径与本机摘要；菜单“打开所在文件夹”已在 Finder 打开相应目录并看到该合成文件，验证后关闭本次 Finder 窗口。通知设置仍为 notDetermined，真实系统通知展示/点击未通过，未再次操作被工具禁止访问的系统授权代理。
- Core0.3.4 独立 App 正常退出后，记录的 Core53562/helper53563 全部自动退出，原 App PID90081 和投屏保留。删除 Mac 本轮 100 MiB/1 GiB 源文件、隔离 App、两个诊断 runtime、大型反汇编与本轮私有 Rust 缓存，删除前分配空间合计约1711.9 MiB；任务根目录复查无 ≥64 MiB 文件和接收 staging。锁定 zip、源码、共享构建及小型证据保留，清单已追加到 /tmp/anydeck-harmony-cleanup-manifest.json。
- 手机仅选中本轮 a–f 六种样本及重复收到的 b-64KiB(1)，共7项，移入“最近删除”，系统提示最长30天可恢复；原目录确认不再有合成文件，个人文件和旧39B测试文本未动，未清空最近删除。后续先处理接收兼容性及通知授权问题，再按需生成大样本；完整目标继续未完成。


## Core 0.3.5 接收终态与 100 MiB 双向（2026-10-29）

- 私有 Core 95574b21510fa26137def60a9ca66412b8251403：接收必须同时满足 helper exit 0、唯一完整成功终态、全部文件大小/hash 校验与原子发布。迟到成功不能覆盖先前失败；取消、期限、文件上限与进程终止分别分类，私有诊断不进入主仓。主仓锁固定 zip SHA-256 c603bcdd028dbd9ab025d6abfaa7bc7b27e243c24e8293e8633c2c89365bd552，IPC3、生产 send/receive=false。
- 准备版完成两次 1 MiB 回传，均与源 SHA-256 一致；默认配置的对照也成功，显式 Wi-Fi 名称实验已撤回。当前网络已变化，本轮重新读取 Mac 地址和广播地址、重新发现 nova 动态端口后才发起传输，未沿用旧地址。
- 最终签名制品向 nova 12 Ultra 发送新建 g-100MiB.bin，用户确认收到；同一文件回传等待 3 秒接受后完成，独立重读落盘 SHA-256 为 8cf88322bd8ea786a0741982a82639faeda2bc3f69e87c5c61bd5e8f988a4aec，与源一致。证据目录 /tmp/anydeck-harmony-core035-real-20261029，摘要 100MiB-roundtrip-verified.json；这是独立 Core 真机结果，尚不替代实际 App 接收确认、历史与 GiB 验收。
- 48 项非 GiB 库/实际签名 IPC、9 项 integration 通过；DFile 8 项测试中 7 项通过、1 项可选 LAN 跳过。主仓 25 项错误/Client/Session tests、targeted analyze、3 项 installer tests 和 Release 构建通过；新错误分类复用既有双语提示，技术错误仅在主动诊断中展示。
- 独立测试 App 已按固定 commit 制品更新，整包 deep/strict、5 成员 hash/签名、Core0.3.5 hello 和 commit 内 zip 摘要核对通过。沿用隔离 bundle ID、设置与记录，不替换或停止原 Debug App；接下来继续运行 App、GiB 双向、系统通知与清理验收，完整目标仍未完成。


## 统一正常测试包与用户接管验收（2026-10-29）

- 用户要求停止双 App 验收并删除全部测试产物。独立测试 App 已退出，其 Core/DFile 子进程全部回收；当时 1 GiB 发送最后记录 604,832,800 bytes，追加 64 KiB 仍在队列，均未完成，不能据此判定 GiB 通过或原生失败。
- 最新 main 已重新构建正常 Debug AnyDeck，并安装锁定 Core0.3.5。bundle ID 保持 com.github.anydeck，包内 5 成员 hash/签名、IPC3 hello、整包 deep/strict 与 Debug JIT entitlement 均核对通过。当前只运行正常 Debug App，实际页面可发现 nova 12 Ultra，本机名称为 AnyDeck；隔离测试记录未迁入正常用户记录。
- 已按用户要求删除独立测试 App、Mac 合成样本和回传副本、隔离配置/SQLite/缓存、任务临时日志/截图/诊断目录、旧安装测试目录、额外 Release 测试包与私有构建缓存。此前本文引用的临时证据路径现已清理；验证结论保留在本地 Git 记录中。正常 Debug 包、项目源码和锁定交付制品保留。手机端由用户确认测试文件已删除。
- 正常通知授权由系统保存，无需每次启动重复允许；不同 bundle ID 的独立测试包与正常 App 分别记录权限。独立包不弹窗但返回 notDetermined 的根因未确认，不能宣称通知送达/点击已通过。参考 Apple 官方文档：https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications 。不再启动独立包或主动创建合成样本，后续手机验收由用户操作正常 AnyDeck。

### 自测顺序与预期

| 步骤 | 操作 | 预期 |
| --- | --- | --- |
| 发现与名称 | 同一 Wi-Fi，手机解锁并开启所有人可见；Mac 打开鸿蒙互联、开启接收。在设置修改本机名称 | 手机看到当前名称；空闲发现有扫描动画；收发期间名称/目录修改禁用 |
| Mac → 手机 | 先选一个现有小文件，再验证现有 100 MiB 至 1 GiB 文件和多文件批次；在手机接收 | 最终显示已完成，记录数量/大小正确；进度与文件实际传输同步 |
| 连续队列 | 大文件发送中追加一个小批次 | 追加项先排队，前一批结束后才发出下一次手机接收请求 |
| 手机 → Mac | 将相同文件同时通过华为分享发送给当前 Mac 名称，Mac 点接收 | 最终完整落盘，批次及逐文件记录完成；源文件与回传文件 SHA-256 一致 |
| 通知与重启 | 在系统设置 → 通知 → AnyDeck 检查允许状态；后台收发完成后点击通知，再重启 App | 通知进入鸿蒙互联页；历史仍在，重启无需重复授权 |
| 取消和失败 | 取消一个批次，或在手机可见期限到期后发起发送 | 不假报成功，记录实际结果；未完成接收不发布成完整文件 |

手机所有人可见有 10 分钟期限；到期后重新开启再测试。可用 shasum -a 256 分别核对原文件与回传文件，不需要再生成合成大文件。100 MiB 独立 Core 双向已通过；正常 App 的 GiB 完整回传、真实系统通知和其他人工验收继续保留未完成状态。
