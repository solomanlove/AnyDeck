# Huawei Share 私有核心集成边界

当前基线：Core 0.3.2 / IPC 3，大文件实验上限 1 GiB 已完成离线验证，生产能力仍未发布。最新证据与限制见本文末尾及 `docs/plans/harmony-share-delivery.md`；早期 1 MiB 与 IPC 1 段落保留为实施历史。

AnyDeck 主仓库仅保存 Flutter IPC 契约、制品锁定清单和安装脚本。协议解析、认证、Swift 广播、DFile 适配、协议测试及原生制品均归独立私有仓库 `solomanlove/AnyDeck-Share-Core`。主仓库当前 `main` 与 `origin/main` 不可达原 PoC 对象；推送前继续用 `git rev-list --objects origin/main..HEAD` 核验历史中没有 `tool/huawei_share_poc`。本机 Codex checkpoint 仍保留旧树，仅属于本地内部引用，不随 `main` 推送。

## 构建链路

1. 私有仓库运行 `script/build_artifact.py`，输出按架构区分的 zip、包内 manifest、每文件 SHA-256；把 Swift BLE helper、DFile helper 和 OpenSSL 3 动态库一起签名和打包。
2. 主仓库 `script/share_core.lock.json` 固定私有仓库 commit、IPC 版本与 zip SHA-256。
3. 构建 Release 时显式设置 `ANYDECK_SHARE_CORE=1`；`script/install_share_core.py`只读取锁定 commit 的制品，逐层校验后写入 `.app/Contents/MacOS/ShareCore/`，再由现有 `fix_macos_app_policy.sh` 签名整个 App。
4. `ShareCoreClient.probe()`通过当前 IPC version 3 握手，只信任显式声明的能力。无二进制或版本不符时失败；不使用外部 Python 或原星河进程。

## 当前验收与未完成项

- P0：私有仓库保留既有43项 Python 协议测试、11项 Swift 测试、DFile 本地双进程测试；Rust 新增有界封包、RSA/AES认证与离线握手测试。
- P1基础：arm64 私有制品可按固定 SHA-256 拉取、安装至隔离测试 App 并执行版本握手。主仓库二进制安装与能力解析测试通过。
- Rust IPC 声明 `discovery=true`、`send=false`、`receive=false`。2026-10-28 原生 CoAP 在局域网发现 nova 12 Ultra；实验发送端完成认证、加密 offer、Bytes/File 通道、DFile 成功回调，手机确认收到 39B 测试 txt。手机通过 Rust 接收端回传同一文件，落盘 SHA-256 与原件一致，手机确认发送成功。同一身份 BLE 广播包含在制品内。双向结果仅覆盖单文件测试命令；一般文件、其他机型、App 包内运行与生产信任策略仍待验证，因此 `send/receive` 不对生产 UI 开放。
- x86_64 制品、Developer ID签名与公证、Release 包内双向真机验收仍待完成。

## 单文件收发自测入口（2026-10-28）

- 接收中心新增「华为分享（测试）」卡片：扫描手机、选择或手填手机 IPv4/端口、选择一个文件发送、选择父目录接收。扫描失败时可直接填手机 IP；本机与广播地址可按实际网段修正。
- Flutter IPC 用显式 `ANYDECK_SHARE_EXPERIMENTAL=1` 仅为本次点击启动单次子进程。`hello` 的 `send/receive=false` 仍表示生产能力未发布；测试界面不将其展示为正式支持。页面退出、用户取消及超时均回收进程。发送文件限普通非空文件 1 MiB 内；接收生成新的 `AnyDeck-Share-<时间戳>` 目录，核心再次校验文件和目录边界。
- 自测路径：使用 `ANYDECK_SHARE_CORE=1 ./script/build_macos.sh <目标目录>` 构建含私有制品的 App；打开「投屏接收 → 华为分享（测试）」。Mac 与手机同 Wi-Fi，手机解锁并开启华为分享。发送时先扫描/填 IP、选文件，手机确认接收；接收时先填手机 IP、选保存父目录，再在手机通过华为分享选择 AnyDeck PoC。只传新建的无敏感小文件，分别核对手机文件和 Mac 接收路径。CLI 响应中的发送完成不等于远端哈希校验，接收 SHA-256 是本机落盘摘要。
- 验证范围：本轮 IPC 边界与页面 Widget 测试、静态分析及打包验证；完整 App 交互和真机双向需要用户在含核心的构建包上自测。AirPlay/DLNA 与其 Provider 未改动。
- 本轮实际验证：9 个定向 Flutter 测试通过；改动文件定向 `flutter analyze` 通过。全仓 `flutter analyze` 仍有 40 条既有告警/提示，未涉及本次改动文件。`ANYDECK_SHARE_CORE=1 ./script/build_macos.sh /tmp/anydeck-huawei-share-selftest` 成功，产物约 94 MiB，其中 ShareCore 约 7.3 MiB；`codesign --verify --deep --strict` 与包内 `hello` 握手通过，测试命令门控可接受。尚未在这份新 App 上进行交互与真机传输验收。

当前集成不会替代 HDC 文件管理，也不与其设备身份自动合并。多窗口只应使用一个 Share Core 进程，后续状态通知需由主窗口统一分发。

## 独立鸿蒙互联入口（2026-10-28）

- Dashboard 全局 Tab `-4` 对应 `/harmony-share`，侧边栏位于投屏接收下方；选中时清空设备管理的当前设备，互联状态不依赖 HDC/ADB。旧投屏接收测试卡片已移除。
- `HarmonyShareService` 由主窗口启动和回收，`ShareNetwork` 从 macOS 网卡真实 netmask 计算广播地址。单个私有核心进程每轮运行最多 120 秒，向页面输出设备摘要和来件 offer；发送时暂停接收进程，结束后恢复。
- 私有核心的 `receive_file_interactive` 仅发送 `incoming_offer` 的手机地址与文件字节数，上层答复 accept/reject；30 秒未答复自动拒绝。接收文件保存在 Downloads 下新建目录，失败/拒绝时私有核心清理空目录。主仓不持有认证或传输协议字段。
- 当前 `hello` 保持 `send=false, receive=false`，实际 UI 明确标注测试版 1 MiB 单文件边界。最近路径保存在本地 SharedPreferences；多文件、进度、系统通知、完整任务模型仍归后续阶段。
- 构建时 `ANYDECK_SHARE_CORE=1` 从私有仓库固定 commit 安装已校验制品；本机可通过 `ANYDECK_SHARE_CORE_ARCHIVE` 指定相同哈希的本地 zip 以跳过远端下载。协议源文件、PoC 和密钥不进入主仓库。

## UI 分阶段落地（2026-10-28）

- 新页面拆分 `HarmonyShareStage`、身份/最近记录/忙碌面板与收发共用确认面板。保留原独立路由与主窗口接收生命周期，不依赖设备管理。样式使用 ColorScheme 与 AppThemeSizes，采用静态同心圆避免持续动画功耗。
- 单文件拖放区与设备卡片不再嵌套；多设备时中央区域不猜测目标，提示拖到对应头像；重复文件选择/确认有门控，文件访问异常有本地化提示。服务关闭时不再显示“正在发现”。
- Widget 验证覆盖 zh/en、Light/Dark、无手机、多设备目标、忙碌禁用、来件拒绝及 480px 窄窗口。视觉测试支持通过 `HARMONY_CAPTURE_DIR` 导出真实 Widget PNG；可选 `HARMONY_CAPTURE_FONT` 使用本机字体，不提交字体文件。
- 本轮 14 项定向测试与 2 项视觉布局测试通过，targeted analyze 无问题。已检查 Light/Dark 空态、附近设备与来件面板截图（`/tmp/anydeck-harmony-ui/`）。测试截图不是运行中 App 真机截图。原 HTML 的 file URL 被浏览器策略拦截，未完成实际渲染逐项对照，阶段 1 视觉验收仍保留该项。
- 本批未修改协议、大小限制、能力声明或制品锁；1 MiB 限制继续有效。完整记录、系统通知、真实进度后续实施，不显示虚假成功百分比。阶段进度与验收入口：`docs/plans/harmony-share-delivery.md`。

## 大文件离线批次（2026-10-28）

- 主仓 `ShareCoreContract` 升级 IPC 2；握手必须显式符合实验上限、进度和 graceful cancel 字段，旧制品拒绝使用。会话从 Client 拆出到 `share_core_sessions.dart`，stdout 流式消费，不保存完整事件列表；最终成功事件才表示任务完成。
- 私有 Core 0.2.0 / commit `21d8bee605793b6183e4f91233c95028df4942d9` 的实验上限为单文件 1 GiB、30 分钟；生产 send/receive 仍 false。主仓只集成元数据和状态事件，协议改动与诊断资料留在私有仓。
- 接收收到 `session_started` 后进入互斥忙碌态并撤销发现 watchdog，网络刷新暂停；进度只接受合法、单调字节数。发送准备时取消也会保留取消意图，避免核心稍后启动后继续发送。先 SIGTERM 清理，5 秒无响应再回收子进程并 SIGKILL。
- 离线压力样本 10/100/512 MiB/1 GiB 均通过加密 DFile 双进程与 SHA-256，1 GiB 最终复验单进程采样峰值 RSS 约 180 MiB；不是手机双向完整链路验证。用户明确先做离线验证，真机阶段待方便时继续。
- 主仓 24 项 focused tests、3 项 installer tests 与 targeted analyze 通过；新增 fake_async 为测试既有依赖的显式声明，用于跨 125 秒的生命周期回归，不增加 runtime 依赖。
- 锁定 zip SHA-256 为 `106026e891b971c8c004c37a9b67213fe2a43cc087a688ba7ec37970b623a119`；新私有 commit 暂未推送，构建使用私有仓本地 zip override。阶段记录和测试包位置见 `docs/plans/harmony-share-delivery.md`。

本轮曾因磁盘空间不足中断一轮验证；只清理本轮已停止合成样本的临时目录后，串行重跑压力测试和 Flutter 验证通过。启动/停止竞态新增独立回归用例，避免异步启动迟到后残留接收进程。

## 多文件发送队列第一批（2026-10-28）

- `share_send_selection.dart` 负责 1–100 文件元数据选择与边界校验，按规范化绝对路径去重；每项开始前检查文件是否变化，不读取内容。私有核心依旧负责流式快照。
- `harmony_share_send_queue.dart` 是串行队列状态机，文件失败后继续，单项/整队取消独立，重复取消幂等，迟到进度/错误总量不污染当前项；字节与最终状态分开。核心最终成功优先于迟到取消，保持最近路径与任务结果一致。
- `HarmonyShareService` 对整个 batch 持有忙碌态，暂停接收一次，所有文件结束后恢复一次。它由主窗口持有，队列不依赖页面生命周期。UI 的多选/多文件拖放共用同一确认与发送入口。
- `HarmonyShareQueuePanel` 展示处理数量、结果数量与真实字节进度，并限制列表高度；`HarmonyShareDropTarget` 用局部 ValueNotifier 控制拖入反馈，不启动持续动画或混入 ADB 安装/上传 Provider。所有新增文件 <500 行，zh/en、Theme 语义色同步。
- 本批 40 focused Flutter tests、targeted analyze 通过；Light/Dark 队列 Widget 截图已检查。原生单文件 IPC 2/私有制品锁保持不变；每项仍需手机确认，原生多文件接收、持久化队列/完整记录、通知、真机回归尚未完成。

## 持久化互传记录第一批（2026-10-28）

- `ShareHistoryDatabase` 在工作 Isolate 管理独立 SQLite/WAL；`ShareTransferHistory` 负责小型摘要缓存、顺序写入、每秒进度检查点、终态保存和重启中断恢复。记录只保存元数据，接收 SHA-256 明确为本机落盘摘要。
- 发送队列通过 onQueued/onChanged 保存所有任务；等待首次落盘期间的取消会重放终态，重试有 retry_of 关联，不覆盖原记录。接收拒绝/确认超时/取消/失败/中断独立；关闭接收器前排空终态消息，晚到的已验证成功可修正取消/中断，但不覆盖明确拒绝。
- UI：首页完整记录摘要、方向筛选、搜索、游标分页、详情复制、路径操作、显式发送重试和仅删除记录。旧路径缓存单独保留，不伪造历史。未知来件文件名保留摘要，成功后补齐。
- `HarmonyShareOfferPresenter` 只关闭持有的 Route，修复确认失效后残留弹窗和误关其他窗口；销毁后不再读取 context。`HarmonyShareSender` 单独持有原生发送会话与订阅，服务文件保持 <500 行。
- 私有 Core 0.2.1 / IPC 2：commit `13ad17f5ffdc4dadca6e80ba1f3a4a9adb51bd71`；固定 zip SHA-256 `56b5836ec9485f4acdd758b5482a8dcd621ed3b202429c2f074d512b117d0c26`。只新增明确 decision_timeout，DFile/认证/Swift 未改，生产能力仍 false。
- 本批 68 项 focused tests、targeted analyze 通过；私有 Rust 19 unit + 4 integration 通过。历史列表/详情 Widget 明暗图已检查。真实手机、Finder 与 App 重启人工验证仍待进行；系统通知、相关设置和原生多文件收发继续推进。详细阶段证据见 `docs/plans/harmony-share-delivery.md`。

## 通知与接收目录（2026-10-28）

- `HarmonyShareNotifications` 由主窗口 Provider 持有，复用全局 MacNotificationBridge；监听实时记录事件与队列完成边界，不重放启动加载的历史。来件生命周期对应撤回，接收终态去重，多文件发送只发一条计数汇总。后台不主动请求系统权限。
- 通知 payload 仅 `type=harmony_share,targetTab=-4`，点击在设备字段解析前直接导航互联页；不执行文件路径或 accept 参数。Swift 原有唤醒/冷启动缓存机制保持不变。通知队列/去重缓存有界，桥接超时与异常不会阻断传输，原生迟到送达仍检查失效并清理。
- 新设置沿用 AppSettingsController 与 SettingsBroadcast：`update_harmony_share_notifications`（bool）、`update_harmony_share_directory`（绝对路径或空字符串）。主/子窗口均更新同一 SharedPreferences key；主窗口接收服务按新轮次读取目录，子窗口不启动接收器或通知协调器。默认目录为空表示 Downloads，默认开关 true 仍受系统权限约束。写入 false/异常时重读 legacy SharedPreferences 缓存，UI 状态不采用未保存值；真实存储完全不可读仍属待验收异常场景。
- `ShareReceiveDirectory` 对显式选择进行临时子目录写入探测，结束清理；不存在的自定义目录不静默回退。设置期间不会移动历史文件；收发忙碌时禁用目录修改，后续接收继续使用独立子目录与核心校验。UI 层持有选择器/权限查询生命周期，纯展示面板独立测试 Theme/l10n。
- 自动验证与打包证据见 `docs/plans/harmony-share-delivery.md` 阶段 4 第二批。系统通知横幅/唤醒、真实选择器、手机收发暂未人工验收；本机名称与原生批量链路仍需继续。

## 原生批次底座离线进展（2026-10-28）

- 私有仓 `b729c88` 增加 1–100 文件原生加密批次 helper 与写盘前完整清单校验；数量在分配前限制，大小/平面路径/名称冲突/既有文件与链接均在写盘前处理。测试与实现材料保留私有仓，不进入主仓。
- batch suite 9 项通过，100 文件与 110 MiB 混合 batch 逐文件 hash、真实总进度通过；12 个直接边界场景与 allocation/NUL 入口通过。既有单文件/大文件和 Rust 回归通过，具体结果见阶段计划。
- 这只证明传输底座，不证明 Rust 生态认证/批次确认、IPC/Flutter 模型、手机兼容性或生产能力。主仓锁定 Core 0.2.1 / IPC 2 不变，私有 zip 未替换；下一步接入真实批次状态机并扩展离线验证。

## Core 内部原生批次离线链路（2026-10-28）

- 私有仓 `83f9aee` 的 Rust 内部 API 完成整批 snapshot、一次确认、实际加密数据链、完整文件元数据校验、流式本机 hash 和不覆盖的整目录原子发布；拒绝/取消/发布竞争均清理本轮 staging。旧单文件入口与批次入口分别限流；源码与模拟资料均留在私有仓。
- 100 文件、三文件混合批次与双角色“1 GiB + 64 KiB”实际 loopback 流程通过，逐文件最终 hash 与独立源 hash 一致。32 常规 lib + 1 显式 GiB 双角色压力用例 + 4 integration、DFile batch/legacy 与 Release 编译通过。SIGTERM 用例先观察真实传输和非空子进程集合，再断言回收与无半批发布。
- 测试专用 Meta 主动端模拟手机，不进入生产构建，也不代表手机/BLE/发现兼容已验收。发送 ACK 不证明接收最终发布成功或远端 hash；UI/IPC 接入时必须保留该区分。
- 对外 IPC 2、Core 0.2.1 zip 和主仓锁未改，Flutter 尚未调用新内部批次 API。下一步版本化通用批次契约与任务模型后再更新制品，不能提前把内部测试结论显示为已支持手机原生批量。

## IPC 3 契约准备（2026-10-28）

- 私有仓 `468f828` 的 Core 0.3.0 新增有界批次 IPC 与严格版本/实验门控，声明大小在全部 snapshot 后逐项复核；最终接收结果分成文件事件与批次摘要，避免超过 JSONL 行上限。生产能力仍关闭。
- 主仓新增独立 ShareBatchContract/Request/Received 模型，包含请求 UTF-8 大小限制与结果完整性/路径/hash/计数检查；当前 ShareCoreContract、Client、运行服务和锁仍为 IPC 2，没有提前启用未打包制品。
- 58 项 nearby_share tests、targeted analyze；私有 32 常规 lib + 5 integration/Release 编译通过。成功 IPC 到实际 App、状态机/记录/通知接线、新 zip/锁和手机验收仍未完成。

## 批次 Client/Session 与制品切换（2026-10-28）

- 主仓握手/安装锁切换 Core 0.3.0 / IPC 3，仍可调用旧单文件命令。新增 ShareBatchClient/Transfer/ReceiveSession 管理原生批次请求、确认、严格进度、逐文件集合与摘要验证；只有完整终态才生成完成结果。资源失败/取消均有回归；实际批次服务/记录/通知/确认 UI 接线仍待完成。
- 私有制品 commit `7059e220004229e7f1df347c667bd11a064ccd16`，zip SHA-256 `2c23cab15e578e3d0d3cfe1cd9268d734f7764bbc84149acdfb4a43cc66c8d58`；生产能力 false。实际新 IPC 命令子进程与 1 GiB + 64 KiB 模式通过，BLE 使用隔离 stub，无真实设备操作。
- 115 focused Flutter tests、targeted analyze、3 installer tests；私有 33 常规 lib + 5 integration 与单独真实 IPC GiB 用例通过。Release 包验证见阶段计划。私有 commit 未推送，使用本地 archive override；未启动/停止用户 App。

## 原生批次接收与文件级记录（2026-10-28）

- HarmonyShareService 正式调用实验批次接收入口；确认摘要包含数量与总大小，整批一次决定。接收事件抽至同库扩展，只有严格匹配 offer、路径/大小/hash/计数和最终摘要的完整结果才更新最近路径及记录。停止会话需等待批次验证流排空，避免 late-success 被取消订阅吞掉。
- 记录库原地增加 file_count/batch_id。多文件成功保存一个摘要和有界子文件清单；首页默认摘要，搜索含子文件，详情一次查询且 Theme rebuild 复用 Future。整批删除级联记录，不删除文件；单文件格式兼容旧库。通知只看批次摘要，目录动作打开实际批次目录。
- 128 focused Flutter tests、targeted analyze、2 Widget 视觉测试通过，Light/Dark 批次详情图已检查。私有测试 commit e040923 通过真实接收 IPC 确认与结果联调，34 常规 lib + 5 integration；隔离 BLE stub，无手机操作。主仓锁/zip 固定7059e22，无生产协议源码变更，生产 send/receive=false。Release 包与验证边界见阶段计划。
- 发送 UI/队列尚未切换原生批次；手机、大文件双向、真实通知/Finder 与 App 交互仍待人工验收。完整持久化故障重试、持续队列与本机名称同步继续处理。

## 原生批次发送与整批进度（2026-10-28）

- 主窗口发送服务使用一次原生批次会话，全部文件 verifyUnchanged 后才启动 Core。HarmonyShareSendQueue 的原生模式与旧串行模式共用记录/通知消费者，但明确整批取消、失败与完成语义，不进行自动逐文件回退。完整有效终态优先于迟到取消，批次标识隔离旧回调；停止服务等待发送结束及记录写入。
- ShareSendBatch 保存不可变文件快照与实际总进度；Core 只给总量时不推测逐文件字节。UI 隐藏活动批次的逐文件取消，确认页与队列显示整批语义，说明远端 hash 未验证。SQLite 保存批次摘要及子文件，失败子文件可显式重试，关联原记录；未知子文件进度在详情明确标出。
- 147 focused Flutter tests、targeted analyze、2 项 Widget 视觉测试通过；Release 包签名、Core/zip hash 和 IPC 3 握手验证通过。未重新运行 Core GiB 压力，不把模型总量测试当作实际传输。制品与私有源码本批未改，仍固定7059e22。详见阶段计划。
- 待完成持续追加队列/速率、文件级真实进度、名称核心同步、存储故障可靠恢复及真机/发布前验收。手机测试仍按用户要求暂缓。

## 记录故障恢复与容量门控（2026-10-28）

- ShareTransferHistory 改用 ShareHistoryWriter：按任务合并最新记录、整批原子补写、在途 revision 校验。默认 1024 个槽位包含活跃批次子文件预留，终态持久化后释放；容量不足在缓存/网络开始前拒绝新任务，已有批次可写完整结果。失败数据不因其他任务写入或缓存淘汰而消失。
- 自动重试 1/2/5/10/30 秒退避、单 Timer、单写入；手动 retryPending/flush 不重发文件，也不重放 changes 成功事件。dispose 结束重试与通知。初始化错误与未保存写入错误分别保留，全部待保存事务提交后才清除写入错误。
- 查询/子文件读取遇到未保存错误时明确失败，避免把旧库/空清单展示为新结果。首页与记录弹窗共用存储重试提示；待保存记录仅保留本次运行，永久故障下仍需用户恢复存储，不能承诺崩溃后恢复未写入的数据。容量错误在 Dashboard/队列/详情统一翻译。
- 166 focused Flutter tests、targeted analyze、2 Widget 视觉测试和 Release 验证通过。真实临时 SQLite trigger 注入子文件写入错误，证实事务回滚及恢复后补齐；路径阻断、自动重试、门控与不重放事件均有回归。未真实填满磁盘、操作手机或启动 App，私有 Core 与锁定制品未变；详见阶段计划。

## 连续队列、周期通知与发送速率（2026-10-28）

- HarmonyShareOutbox 在原生单批队列外串行调度，最多 8 个活动/待发批次；新选择独立确认，不修改正在传输的批次。排队即提交稳定 ID 的 queued 记录，runPrepared 沿用 ID，文件/网卡在每批启动时复核；存储故障继续受 ShareHistoryWriter 约束。
- UI 可在发送时选文件/拖放追加，提供待发批次取消、当前批次取消和全部取消。批次失败/当前取消后继续下一批，整体取消停止追加；一段队列只暂停/恢复接收一次。发送编排拆至 harmony_share_send_service.dart；stopWindow 在发送操作存在时不自动启动接收器，防止迟到来件破坏互斥，并在停止排空后清理迟到 watchdog。
- 待发列表有界，精简已完成展示仍保留累计计数；完整历史在 SQLite，重启将未完成记录恢复为 interrupted，不自动重发。系统通知改为原生连续队列结束后汇总一次，周期 ID/计数先捕获，隐私/权限/点击路由沿用既有机制。
- ShareTransferRate 基于单调时钟与真实字节窗口，样本有界；初始/停顿/100% 等待终态/取消结束均不伪造速度或 ETA。估算只针对当前发送批次，过期刷新为 1 Hz，失效后停止 Timer。文件级真实进度仍待 Core 提供。
- 187 focused Flutter tests、targeted analyze、2 Widget 视觉测试与 Release 验证通过。临时库与模拟 Client 用于状态链验证；截图速率为合成 fixture，本批不重跑真实 Core GiB 压力，也不宣称手机吞吐。私有制品/锁保持7059e22，生产 send/receive=false；详见阶段计划。

用户要求最后清理本次大文件。2026-10-28 已在完成校验后删除 12 份隔离 App 与私有 core/target 缓存，约 2.1 GiB，当前可用约 3.5 GiB；历史临时 App 路径不再存在。源码、锁定 zip、日志/小型截图保留，共享/在用构建与其他来源缓存未动。后续按低存储约束验证并清理新生成的临时大文件，不能依赖旧 target 或临时 App 仍存在。

## 本机名称的 Core 准备（2026-10-28）

- 私有仓5bfaf66的 Core 0.3.1 源码新增按会话持有的 local_name：发现、原生批次发送/接收与 Swift helper 保持同一快照；默认 AnyDeck，最大24 UTF-8字节且拒绝非法控制/空白输入。hello 增加 batch_local_name/max_local_name_bytes，旧单文件命令不默默接受名称字段；生产 send/receive 仍 false。
- 36 Rust lib +6 integration、12 Swift tests、Rust Release 与 hello 通过；真实 loopback offer/meta、接收 IPC helper argv/接收 meta/文件 hash 已验证。BLE 用隔离 stub，Swift 只验证参数与实际广播字典，未验证无线空口或手机显示。
- 主仓当前运行契约/锁定制品保持 Core 0.3.0（7059e22），未打包0.3.1。下一批需接 Flutter设置/同步、Dart同边界校验、显式能力门控与新制品，不提前开放只改 UI 的名称设置。
- 本批无主仓功能代码改动；已追加阶段记录。按用户要求清理本轮 Rust/Swift 缓存约528.5 MiB，不重建 GiB 样本；当前可用约2.3 GiB，源码与旧 zip 保留。

## 本机名称设置、主窗口写入与 Core 0.3.1 制品（2026-10-28）

- AppSettings 的 harmonyShareLocalName 默认 AnyDeck。ShareLocalName 统一校验24 UTF-8 bytes 与特殊字符；名称编辑器展示字节数、保存/恢复，中英文与明暗主题覆盖。HarmonyShareIdentity 使用服务已读取的名称，原生批次收发/发现 IPC 传 local_name；握手强制声明名称能力，旧制品不静默忽略。
- 名称设置由主窗口独占写入：子窗口 change_harmony_share_local_name 先请求主窗口，主窗口配置预留阻止新收发；收发忙碌时拒绝，空闲保存先停接收，失败恢复旧配置，完成后新会话读取一次。主窗口通过既有广播通道发 update_harmony_share_local_name；接收方重读最新落盘值，避免旧广播覆盖新值。设置与 UI 不直接操作协议或蓝牙。
- 新锁固定私有 c5177809fda428b1847c852472710b3bfed4ec00，Core0.3.1/IPC3，zip SHA-256 08296ff0cdaadec21758499ac860085366530fd6bd8a30085210d2de237485e4；生产 send/receive=false。未 push，构建使用本地 archive override。197 focused Flutter tests、targeted analyze、3 installer tests、2额外 Widget 渲染测试与 Release 包严格签名/hash/hello 校验通过，详见阶段计划。
- 验证后清理本轮独立 App 与 Rust/Swift 缓存约234.6 MiB，已在/tmp清单记录；保留锁定 zip/源码/小型日志截图，私有 .DS_Store 和共享构建未动。未启动/停止用户 App、操作手机/真实 BLE 或重跑 GiB 压力；真实空口名称、文件级进度、手机大文件双向及完整发布验收仍待完成。

## 扫描动画与文件进度准备（2026-10-28）

- 服务scanning只反映真实空闲发现窗口。独立ScanBackdrop/Painter以AnimationController驱动装饰重绘，3秒双波纹对齐中央投递区；收发/配置/关闭/错误不扫描，减少动态效果/无障碍/TickerMode停止，Dashboard离页销毁。空设备与设备卡片换行后的圆心几何已验证，不影响拖放命中；本机改名继续可用。
- 主仓203 focused tests、targeted analyze、2额外Widget导出与Release严格签名/hash/hello通过，详见阶段计划。当前App锁/zip仍为Core0.3.1/c517780，不能依据私有源码准备宣称App有单文件进度。
- 私有60810f0为真实socket/文件写入增加有界逐文件bitmap计数；17项原生回归通过、1可选LAN跳过。6ca9ade的Core0.3.2新增严格file_progress校验，并用逐文件IO值汇总总量，legacy事件集不变；40全库lib+6integration+4专项/Release/hello通过。Flutter模型/队列/接收展示/记录检查点及0.3.2制品切换继续推进。
- 本轮删除Rust缓存、新clone和隔离App约363.1 MiB，清单已追加；Core target当前不存在，已有小型DFile构建底座保留。未push/启动App/操作手机或真实BLE，真机与最终发布验收继续暂缓。

## 文件进度 App 接线与 0.3.2 制品（2026-10-28）

- ShareCoreFileProgress继承通用进度，ShareFileProgressLedger限制数量/大小/索引/单调性及最终结果一致性；发送依声明、接收按已知项核对总量。队列文件与整批进度分离，保留失败/取消字节；接收只在用户接受后展示，未知文件用稳定序号，不伪造0%或文件名，100%仍等待整批结果。
- SQLite增加progress_known/file_index，部分接收检查点和终态以原有完整事务/容量预留/失败重试保存，未发布文件无路径。旧库可迁移、完整成功补齐实际文件名/路径/hash，详情区分未知与真实字节；没有路径不显示打开文件/目录菜单。
- 当前锁固定20893ba4307af53bfeec8851fff4d10f9a59c68a的Core0.3.2/IPC3，zip SHA-256 f356fda56a569bdd9418b449bc18b57ceaf87747d8a0780253dd7fc0ceb64ea2，hello要求file_progress，生产能力仍false。227 focused tests、targeted analyze、3 installer tests、2额外Widget渲染及最终Release签名/hash/hello通过。制品真实小文件双向/legacy三项、72f5163的签名制品GiB双向中途进度/完整结果/源hash通过，详见阶段计划。
- GiB样本限定到独立TMPDIR、方向串行并检查6 GiB余量；每轮结束确认空目录并删除根目录。测试后删除Rust/Swift缓存和独立App，含菜单保护重建后再清理的App，约467 MiB分配空间，清单已追加；Core target/Swift .build当前不存在。已有小型DFile底座、锁定zip与小型日志截图保留，未push/启动App/操作手机或真实BLE，手工/真机/最终发布验收仍待完成。


## 用户错误说明与主动诊断（2026-10-28）

- formatShareError 由独立 UI helper 统一处理公开 IPC/异常边界，原入口继续 export；明确原因提供 zh/en 恢复建议，未知内容不直接显示路径或原始错误码。原始错误仍保留在服务/记录，发现页和文件/批次详情通过主动“技术详情”本地查看；批次摘要显示失败说明，发现页回调捕获当前错误快照。
- 235 focused tests、targeted analyze、3 installer tests 通过；最终 8 错误交互与 2 带字体 Widget 导出复验通过。截图边界包含 Navigator overlay，已检查明暗提示及诊断弹窗。最终 Release 签名、成员 hash、锁定 zip 与 0.3.2 hello 通过；验证后删除临时 App 约97 MiB，没有新增大样本，之前 GiB 根目录和 Rust/Swift 缓存仍不存在。
- 本批不改 Core 制品或能力声明，锁仍为20893ba / f356fda56a569bdd9418b449bc18b57ceaf87747d8a0780253dd7fc0ceb64ea2，生产 send/receive=false。未运行 App 或操作手机，手机及人工/发布验收继续待完成；以阶段计划末尾的需求验收表为当前证据边界。


## 通知权限查询失败与恢复（2026-10-28）

- 共享 MacNotificationBridge 的权限异常/空值/畸形或未知响应返回 unknown，不再伪造成 notDetermined；明确合法授权状态不变。互传协调器对查询失败提供 deliveryFailed 提示，后续成功通知恢复；拒绝/未申请不误报；停用/销毁/来件失效后的超时与迟到失败不覆盖当前健康状态，迟到成功仍撤回，也不后台申请权限。
- 259 项相关回归和 targeted analyze 通过，包括实际 Dart MethodChannel + 协调器组合及明暗/双语窄窗口 unknown 提示。原生即时通知的 pending 清理怀疑经 SDK 头文件核对不成立，本批未改原生通知代码或 Core 制品；手机及真实系统交互仍未验收。
- 最终生产源码 hash 一致，Release 构建、严格签名、5 成员 hash、锁定 zip 与 0.3.2 hello 通过；本阶段三次临时 App 产物均删除，按删除事件累计约290.9 MiB，旧 GiB 样本及私有 Rust/Swift 缓存仍不存在。验证未启动/停止 App 或操作真实设备/通知，未 push。

## 独立 App 首轮真机与窗口边界（2026-10-28）

- 用户现已授权独立 App 验收，手机确认 AnyDeck-Test 可见；64 KiB 回传文件的大小和源 SHA-256 一致，另有 1 MiB 单向成功。原生两文件批次存在连接失败、0 B 等待和未确认原因的 phone_rejected，手机多文件/GiB 和真实通知仍未通过，详见阶段计划末尾。
- 接收窗口主动排空时仅抑制全局错误提示，保留历史与末尾成功处理；活动接收错误继续显示。自然结束发现窗口或重新启用时清理 peers，避免把旧窗口缓存当成仍可见设备；发送暂停接收时保留目标。新增 6 项回归，265 项相关测试、analyze、Release 与严格签名通过，Core 锁不变。
- 独立 App 退出曾遗留接收 Core，已仅清理本次路径/PID，后续需修复父进程退出边界；用户原 App 保持运行。测试包、合成样本与记录均在独立目录，后续验收后按低存储要求清理。

## Core 0.3.3 制品切换（2026-10-28）

- 用户确认此前两文件请求未出现、没有手动拒绝，并手动允许测试 App 通知。私有仓修正批次数量一致性与宿主退出回收，40 项非 GiB 原生回归、8 项 integration（含签名制品父进程退出）通过；实际手机复验继续，不能据此宣称多文件已通过。
- 当前主仓锁为 05d7e41911eff34509d17aa9dd7e7317c16b80fe / Core0.3.3 / IPC3，zip SHA-256 2350f8979dc49a4c0aae5d52be6b012164d887cf8ede3d7a0565aab24638460d，生产 send/receive=false。3 项 installer tests、更新独立包 deep/strict、5 成员 hash/签名与 hello 通过；Flutter 源码保持上一批 265 项通过版本。新测试包沿用隔离设置与历史，原有 App 不停止。

## 大文件发送实测与 Core 0.3.4（2026-10-29）

- 独立 0.3.3 App 已实际发完 100 MiB+1 GiB，并在大文件传输中追加 64 KiB 后续批次；用户确认全收，50 个 GiB 中途检查点落盘。0.3.3 真实 App 退出已回收 Core/helper，原 App/投屏保留。小文件诊断回传 hash 一致，但 App 等待确认后的接收仍失败，详见阶段计划，不能宣称双向大文件通过。
- 用户已允许经连接的 nova 自主测试。诊断确认手机选择 P2P 模式时数据连接未到 LAN 端口；相关试验已撤回，不切换 Mac 网络。当前实验版明确报告 unsupported_network_mode，并用中英文提示其边界；空闲发现到期改为正确的 deadline。协议与诊断留私有仓。
- 当前锁 ca77499fc94fcaf449b399ac506ddf734c520137 / Core0.3.4 / IPC3，zip SHA-256 ba685fcccbc8c9666f13bbfd063c1e90e3fc1c98b320773a1cda3542eced27fb，生产能力仍 false。41 项非 GiB 原生回归、9 integration、265 Flutter tests、analyze、3 installer 与新 Release 签名/5 成员 hash/hello 通过。LAN 大文件回传、真实通知/Finder及最终清理仍待完成。
