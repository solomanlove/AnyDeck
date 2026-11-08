# Huawei Share 私有核心集成边界

当前核心：Core 0.3.8 / IPC 3，新增默认 LAN、手动授权的 P2P 直连接收与网络恢复保护，最终制品版本以 `script/share_core.lock.json` 和包内 manifest 为准。Core 0.3.7 已移除应用层单文件1 GiB限制，1 GiB以上的手机收发由用户手动测试。历史Core0.3.5已完成100 MiB独立真机双向hash验证与正常App的1 GiB单文件接收（手机源hash未比对），不代表新版大文件容量、P2P 或共存验收；生产能力仍未发布。最新证据与限制见本文末尾，早期段落保留为实施历史。

AnyDeck 主仓库仅保存 Flutter IPC 契约、制品锁定清单和安装脚本。协议解析、认证、Swift 广播、DFile 适配、协议测试及原生制品均归独立私有仓库 `solomanlove/AnyDeck-Share-Core`。主仓库当前 `main` 与 `origin/main` 不可达原 PoC 对象；推送前继续用 `git rev-list --objects origin/main..HEAD` 核验历史中没有 `tool/huawei_share_poc`。本机 Codex checkpoint 仍保留旧树，仅属于本地内部引用，不随 `main` 推送。

## 构建链路

1. 私有仓库运行 `script/build_artifact.py`，输出按架构区分的 zip、包内 manifest、每文件 SHA-256；Core 0.3.8 的六个原生成员为 Core、Swift BLE helper、Swift 网络恢复 helper、DFile helper 和两份 OpenSSL 3 动态库，逐个签名和打包。
2. 主仓库 `script/share_core.lock.json` 固定私有仓库 commit、IPC 版本与 zip SHA-256。
3. Runner 的 `Embed Share Core` 阶段在 Debug/Profile/Release 构建时自动调用 `script/embed_share_core.sh`；安装器只使用锁定 SHA-256 的私有制品，原生文件写入 `.app/Contents/MacOS/ShareCore/`，manifest 写入 `Contents/Resources/ShareCore/manifest.json`，随后由 Xcode 签名整个 App。无需设置 `ANYDECK_SHARE_CORE=1`。
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

## 自主接收复验、Finder 与清理（2026-10-29）

- 实际0.3.4 App 的两文件回传进入数据阶段，但在1,073,290,790 bytes后 dfile_failed，未发布完整文件或获得回传 hash；另三次100 MiB（含用户手动对照）因 unsupported_network_mode失败。确认后传输期限源码已为1800秒，不能仅按用时归因为两分钟超时，也不能把重试/及时确认宣传为已验证的恢复办法。现已修正中英文提示，新增4项窄窗口错误交互回归，本次12项相关 tests及analyze通过；完整双向验收未完成。
- 记录菜单实际在Finder打开此前已校验的64 KiB文件目录，路径与本机摘要展示正确。系统通知仍notDetermined，展示/点击未通过；不绕过系统授权工具限制。0.3.4测试App退出后Core/helper全部自动退出，原App/投屏保留。
- 本轮Mac的100MiB/1GiB样本、隔离App、诊断runtime、大反汇编与私有Rust缓存已删除，约1711.9 MiB；根目录无≥64MiB文件和staging，保留源码/锁定zip/共享构建/小型证据。手机仅7个本轮合成文件移入最近删除，可恢复30天，未清空或触碰个人文件。历史临时App与大样本路径当前已不存在，后续不可直接复用。


## Core 0.3.5 终态与真机验证边界（2026-10-29）

- 私有 Core 95574b21510fa26137def60a9ca66412b8251403：接收必须同时满足 helper exit 0、唯一完整成功终态、全部文件大小/hash 校验与原子发布。迟到成功不能覆盖先前失败；取消、期限、文件上限与进程终止分别分类，私有诊断不进入主仓。主仓锁固定 zip SHA-256 c603bcdd028dbd9ab025d6abfaa7bc7b27e243c24e8293e8633c2c89365bd552，IPC3、生产 send/receive=false。
- 准备版完成两次 1 MiB 回传，均与源 SHA-256 一致；默认配置的对照也成功，显式 Wi-Fi 名称实验已撤回。当前网络已变化，本轮重新读取 Mac 地址和广播地址、重新发现 nova 动态端口后才发起传输，未沿用旧地址。
- 最终签名制品向 nova 12 Ultra 发送新建 g-100MiB.bin，用户确认收到；同一文件回传等待 3 秒接受后完成，独立重读落盘 SHA-256 为 8cf88322bd8ea786a0741982a82639faeda2bc3f69e87c5c61bd5e8f988a4aec，与源一致。证据目录 /tmp/anydeck-harmony-core035-real-20261029，摘要 100MiB-roundtrip-verified.json；这是独立 Core 真机结果，尚不替代实际 App 接收确认、历史与 GiB 验收。
- 48 项非 GiB 库/实际签名 IPC、9 项 integration 通过；DFile 8 项测试中 7 项通过、1 项可选 LAN 跳过。主仓 25 项错误/Client/Session tests、targeted analyze、3 项 installer tests 和 Release 构建通过；新错误分类复用既有双语提示，技术错误仅在主动诊断中展示。
- 独立测试 App 已按固定 commit 制品更新，整包 deep/strict、5 成员 hash/签名、Core0.3.5 hello 和 commit 内 zip 摘要核对通过。沿用隔离 bundle ID、设置与记录，不替换或停止原 Debug App；接下来继续运行 App、GiB 双向、系统通知与清理验收，完整目标仍未完成。


## 正常包交接与测试产物清理（2026-10-29）

- 用户改为自行操作正常 AnyDeck，要求不再并行运行独立测试 App。正常 Debug 包已重新构建并安装锁定 Core0.3.5，沿用 com.github.anydeck；5 原生成员 hash/签名、整包 deep/strict、IPC3 和 Debug JIT entitlement 通过。当前只保留一个运行实例，设备名称为 AnyDeck。
- 独立包的 1 GiB 发送在用户要求切换时尚未结束，追加 64 KiB 排队未开始，不计入成功或协议失败；独立配置/记录不迁入正常用户目录。
- 独立 App、合成源/回传文件、隔离 SQLite/偏好/缓存、临时诊断/日志/截图、旧安装测试目录、额外 Release 测试包和私有构建缓存均已删除，用户确认手机测试文件已删除。本文此前引用的临时证据路径已清理；保留源码与锁定交付制品，后续自测顺序及未验收边界见阶段计划末尾。
- 系统通知正常只需首次授权，独立 bundle ID 的权限不能替代正常 App。独立包 notDetermined 且无弹窗的原因仍未确认；真实通知和正常 App GiB 回传尚未完成，不再主动创建样本或启动独立包。


## 授权申请交互故障保真（2026-10-29）

- Native 授权 error 原先被忽略；现透传 FlutterError，交互设置使用严格请求入口，旧后台 bool API 保持兼容。申请后复查真实状态，调用失败或仍未确定时保留原权限状态并提供系统设置入口；明确拒绝不报成系统故障。刷新确定状态清除提示，关闭弹窗后不再读取权限或更新已销毁状态。
- 22 项实际设置弹窗用例与通知/设置回归合计 74 tests、targeted analyze 通过；Swift 文件 typecheck 使用未改窗口的 NSWindow 接口占位，不替代整包构建和真实系统通知验收。具体范围见阶段计划末尾。
- 用户自测尚在进行，当前运行包保持交接版本，本批源码修复在下次正常构建后生效。未生成新 App 或传输样本，临时检查目录与测试缓存清理完成，完整目标未标记完成。


## 用户自测的正常 App 1 GiB 接收记录（2026-10-29）

- 用户继续自行测试期间，只读正常 bundle 的 SQLite 与接收文件 stat。nova 12 Ultra 的 receive-1793238368615964-1 为 succeeded，数量 1、声明/累计/实际普通文件大小均为 1,073,741,824 bytes，记录含合法 SHA-256。未读取文件内容或记录原始文件名；仅凭本机摘要不能认定与手机源 hash 一致，完整双向/多文件验收仍未完成。
- receive-1793238289461641-0 在 43,908,150 bytes 处为 cancelled，未记录发布路径或 SHA-256。该结果证明取消记录保留实际进度，未把取消列为完成。用户当前自测接收副本仍保留供其使用，收尾清理尚待这轮结束。
- 正常 App PID1092 持续运行，包内 Core0.3.5/IPC3 的 5 成员 hash 与 manifest 一致；当前无 DFile 活动子进程。没有启动测试包、重启 App、创建样本或改动自测文件。本批只更新验证记录，94a6c0e 的授权源码改动仍待正常重建后生效。


## 鸿蒙互联卡片标题栏精简（2026-11-06）

- 移除卡片内重复的“附近设备”标题、说明、状态 Chip 及分隔线；接收身份栏直接位于卡片顶部。页面级标题与设置/刷新操作、收发状态面板和错误详情入口继续承担各自职责。
- 改动仅位于 `harmony_share_dashboard_tab.dart` 的展示层，未引入依赖、Provider、跨窗口消息或进程行为变更；沿用既有 Theme 与 l10n，不涉及投屏和私有协议。
- 回归入口：`harmony_share_dashboard_tab_test.dart` 覆盖 zh/en、Light/Dark 下重复内容消失、身份栏顶部无残余空白，以及原有开关、舞台、连接指引和窄窗口布局；`harmony_share_visual_test.dart` 提供离线 Widget 渲染验证。人工查看时，卡片应从接收身份栏开始，错误仍通过下方详情卡片呈现。
- 本次上述 10 项 Widget 测试、改动 Dart 文件的 targeted analyze、测试文件格式校验与 `git diff --check` 均通过；未启动、重建或替换用户的 App，实际运行包将在后续构建后体现该布局。


## 正常 Debug / Release 自动打包组件（2026-11-07）

- 触发原因：普通 Debug 构建没有执行原来的可选 Release 安装分支，运行包缺少 `ShareCore`，页面因此提示组件缺失。现由 Runner 公共 `Embed Share Core` 阶段调用 `script/embed_share_core.sh`，覆盖 Flutter CLI 与 Xcode 的 Debug/Profile/Release；安装失败会终止构建，不再生成缺少组件的成功包。旧 `ANYDECK_SHARE_CORE` opt-in 不再参与判断。
- 制品入口：显式 `ANYDECK_SHARE_CORE_ARCHIVE` → 校验缓存 `build/share_core/<SHA-256>.zip` → 相邻 `AnyDeck-Share-Core/artifacts/` 的锁定制品 → 私有 Git 的固定 commit。显式文件错误直接失败；默认缓存/相邻文件不匹配时继续寻找锁定版本。远端获取仍需要私有仓库访问权限，不自动修改锁或升级版本；主仓不检出协议源码。
- 安装前同时验证 zip SHA-256、唯一成员集合、总解压大小、manifest 的 IPC/目标架构及每个文件 SHA-256。目标架构取 Xcode `ARCHS`，当前仅锁定 arm64，未发布的 x86_64 或多架构请求明确失败，不能偷偷使用宿主版本。
- `--replace` 仅由构建入口用于增量更新；成员内容及可执行权限一致时复用，损坏/旧版则先准备完整临时目录，再替换并清理旧成员。发布原生目录或 manifest 失败时还原原生组件，旧 manifest 保持可用。默认手动安装仍拒绝覆盖已有目录，符号链接目标被拒绝。
- macOS 目录规范：5 个已签名 Mach-O 放在 `Contents/MacOS/ShareCore/`，manifest 放在 `Contents/Resources/ShareCore/manifest.json`。把 JSON 留在 MacOS 嵌套代码目录会让普通签名失败；对整包传入 `--deep --entitlements` 又会修改 helper 权限及字节，因此构建沿用 Xcode 正常签名，并迁移旧布局。运行时核心路径与 Dart IPC 不变。
- `script/build_macos.sh` 复用 Runner 自动安装，取消重复安装和提前删除目录；`fix_macos_app_policy.sh` 重签保留 entitlements、requirements、flags 与 runtime，保留 Debug JIT 以及 Release 权限。无新增 Provider、UI、l10n、Theme、窗口广播或运行期进程行为。
- 交叉配置签名保护：`build_device_bridge.sh` 在 Xcode 环境中仅生成桥接库，由当前 Runner 阶段拷贝到当前产物；不再同时改写另一配置已签名 App 的动态库。独立执行脚本的原有更新行为保留，增加离线脚本回归验证边界。

正常使用与定向回归命令：

```bash
flutter build macos --debug --no-pub
flutter build macos --release --no-pub
python3 -m unittest discover -s test/script -v
flutter test --no-pub test/core/nearby_share/share_core_client_test.dart test/core/nearby_share/share_core_sessions_test.dart
```

测试范围：离线构建入口覆盖 Debug/Release 无 opt-in、重复安装、空格路径与错误架构；安装器覆盖缓存、固定制品校验、旧布局迁移、损坏修复和发布回滚；macOS 最小签名包覆盖整包 deep/strict、Debug/Release entitlement 与 runtime 保留、helper 字节不变。

本次验证：24 项 Python 构建/安装/签名回归与 13 项 Dart IPC 测试通过，Shell 语法、Xcode project plist 与 `git diff --check` 通过。取消两个 `ANYDECK_SHARE_CORE*` 环境变量后，正常 arm64 Debug/Release 均构建成功；连续构建后两个包同时通过 5 成员 SHA-256/签名、资源 manifest 一致性、整包 deep/strict、声明权限保留（Debug JIT）及实际 Core 0.3.5 / IPC 3 hello 与完整能力契约核对。未主动启动或重启 App，未传输手机文件；这些检查不代表手机双向传输验收。构建仅使用本机校验制品/缓存，私有远端获取路径由离线 mock 验证，未声称新的远端下载验收。


## 移除首页实验版常驻说明（2026-11-07）

- 按用户截图移除主卡片下方的“实验版：同一 Wi-Fi 下单文件上限 1 GiB，大文件待真机验收”，同时删除专用中英文资源及前置间距；最近互传区域沿用正常段落间距。
- 大小与批次限制继续由现有契约校验，并在文件选择失败时给出明确提示。页面回归覆盖 zh/en、Light/Dark 下该常驻文案消失、连接指引及窄窗口布局。
- 本次 10 项页面/布局测试与 3 个改动 Dart 文件的 targeted analyze、`git diff --check` 通过；未启动、重建或重启 App。

## 来件优先使用 macOS 通知确认（2026-11-07）

- `HarmonyShareIncomingNotifications` 统一持有来件生命周期，`HarmonyShareNotifications.incoming` 由主窗口 Provider 持有。系统通知提供本地化“接收 / 拒绝”操作；按钮直接处理当前请求，不抢占窗口焦点。点击正文打开主窗口并显示原确认弹窗，主动关闭通知也转入弹窗兜底。
- 通知设置关闭、权限未授予/未知、旧桥接不支持、API 错误或超时，均使用原 `HarmonyShareConfirmDialog`。系统提交成功不等于横幅可见，所以请求到达 10 秒仍未处理也显示弹窗；请求总期限从到达起固定为 30 秒，兜底不会重置期限。后台不主动申请通知权限。
- 新增 MethodChannel `showIncomingFileOffer`，参数为 `id/title/body/acceptLabel/rejectLabel/payload`。Native 注册固定 `harmony_share_incoming` 类别并保留其他类别，接收按钮要求解锁认证。正文和 payload 不包含设备名称、文件名、目录或可执行路径；普通收发结果通知继续使用原入口。
- payload 仅含 `type=harmony_share_offer` 与本次请求随机 128-bit `offerToken`。Native 根据系统 actionIdentifier 和实际 request.identifier 覆盖回调的 `notificationAction/notificationId`；Dart 需同时匹配当前 offer、token 和 ID 才能决定。冷启动残留、重复操作、畸形动作和旧弹窗回调均不能影响新请求。
- 接收/拒绝/过期/替换/销毁会取消计时并撤回 pending 与 delivered 通知。迟到的投递结果仍尝试撤回；启动清理超时期间只用弹窗，保留底层清理 Future，真正完成后后续来件恢复通知，明确失败则允许下一请求重试。
- `HarmonyShareOfferPresenter` 只负责原弹窗的显示与专属 Route 清理，通知优先逻辑不依赖页面是否可见。未更改私有 Core、收发协议、接收目录、多窗口同步或投屏行为；原弹窗复用现有 Theme，中英文通知按钮由当前语言提供。

定向回归：

```bash
flutter test --no-pub test/core/nearby_share/harmony_share_incoming_notifications_test.dart test/core/nearby_share/harmony_share_notifications_test.dart test/features/harmony_share_offer_presenter_test.dart
flutter test --no-pub test/mac_notification_bridge_test.dart test/core/nearby_share/harmony_share_notification_permission_test.dart test/features/harmony_share_permission_request_test.dart test/features/harmony_share_settings_test.dart test/harmony_share_settings_test.dart test/notification_forwarding_test.dart test/notification_click_target_test.dart
```

原生离线回归：将 `macos/Runner/NotificationBridgeService.swift` 与 `test/native/notification_interaction_test.swift` 一起用 `xcrun swiftc` 编译；`-F` 与 `-rpath` 指向 Flutter SDK 的 `bin/cache/artifacts/engine/darwin-x64/FlutterMacOS.xcframework/macos-arm64_x86_64`，链接 `-framework FlutterMacOS`。测试自带 `MainFlutterWindow: NSWindow` 接口占位，验证系统动作映射、伪造字段覆盖、聚焦策略与普通通知兼容，不调用通知中心或创建 App。

人工验收边界：正常 AnyDeck 授权后分别从手机发起请求，检查前台/隐藏窗口时通知按钮、正文点击、通知关闭、10 秒兜底及 30 秒超时；再检查禁用通知或 Focus 模式时的兜底，以及普通 Android 消息通知点击。自动测试不代表真实系统横幅或手机传输验收，本轮不主动运行或重启 App。

本次验证：107 项 Flutter/Dart 测试（46 项来件协调/弹窗/结果通知，61 项权限/设置/桥接与普通通知回归）、6 项原生动作映射场景、12 个相关 Dart 文件的 targeted analyze 均通过。原生桥接使用真实 FlutterMacOS Framework 编译并执行上述离线测试；未进行整包构建或真实 Notification Center 交互。审查修复了启动清理超时后的后续请求恢复，并检查提交不包含其他并行任务的改动。


## 首页波纹贯通与手机版本要求（2026-11-07）

- 需求：扫描水波纹延伸到顶部接收身份栏与底部连接提示栏下方，参考用户提供的效果图；补充“手机版本要求：HarmonyOS 6.0.0.112 及以上”。该版本来自用户参考图，作为连接前提说明，不是读取手机实时版本，也不新增版本检测或兼容性承诺。
- `HarmonyShareStage` 新增可选 `header/footer`，统一承载透明上下栏与 Theme 径向渐变。扫描绘制层预留最大波纹直径 790px，中央 Stack 不裁剪，仅由舞台/主卡片统一裁剪；设备卡片换行后波纹仍以中央投递区为圆心。动画继续由独立 RepaintBoundary 和 Painter 驱动，不因帧变化重建前景，停用、无障碍及离页回收规则不变。
- 版本文案通过 `harmonySharePhoneVersion` 提供 zh/en 两种语言，位于连接提示上方，窄窗口自然换行。无新依赖、Provider、跨窗口协议、CLI、投屏或收发逻辑改动。
- 自动回归：页面测试覆盖 zh/en、Light/Dark 的版本展示及上下栏绘制覆盖；扫描测试比较上下栏真实像素帧变化，保留多设备换行圆心、禁用/TickerMode/无障碍/离页停止的验证；视觉 fixture 校验页面与收发面板布局。运行 `flutter test --no-pub test/features/harmony_share_dashboard_tab_test.dart test/features/harmony_share_scan_test.dart test/features/harmony_share_visual_test.dart`，并对 6 个改动 Dart 文件执行 targeted `flutter analyze --no-pub`。
- 人工验收：后续正常构建后，在发现状态查看波纹经过上下栏且不越出主卡片，切换主题/语言并缩窄窗口；保持接收开关、连接指引和设备发送入口可用。本轮仅离线 Widget 渲染与分析，不启动或重启用户 App，不代表手机真机收发验收。

本次验证：18 项页面/扫描/视觉测试全部通过，6 个相关 Dart 文件的 targeted analyze 无问题，`git diff --check` 通过；已查看 Light/Dark 离线渲染图并确认上下栏背景连续、版本提示可读。


## 发现舞台固定高度与批次头像状态（2026-11-07）

本节替代上一节“以中央投递区为圆心”的布局细节；波纹仍贯通上下栏，但统一位于前景文字和头像下方。

- 需求：设备采用参考图中的圆形手机头像，分别展示待接收双点、发送进度环、已发送及异常状态；无手机默认展示“正在搜索设备…”，有无手机和批次状态变化不改变背景高度。
- 布局：`HarmonyShareStage.contentHeight` 固定为 396px。上下栏保持原有自然高度；有设备时左上方展示“附近”和设备网格，更多设备在区域内滚动。无设备时只展示居中状态文本，移除原中央大圆、选择按钮及中央拖放入口，选择与整组拖放均在目标头像完成。`harmonyShareDropHint` 同步更新。背景在整个 Stage 下层绘制，圆心和背景尺寸不再受设备数量影响。
- 数据、逻辑、样式：`model/harmony_share_peer_state.dart` 根据不可变批次快照计算展示状态；`widgets/harmony_share_peer_avatar.dart` 负责头像、文字、点击和拖放；Stage 只编排布局。配色使用 ColorScheme，所有文案支持 zh/en；长名称/英文状态限制行数，网格高度适配 TextScaler，窄窗口和大字体通过内部滚动保持可达。
- 批次来源：原生发送直接使用 `outbox.entries/activeId`；旧串行模式才使用 `sendQueue.batch`，避免重复计入原生批次。按 IP + 名称隔离设备，同名设备重新发现后操作使用新端口。当前活动批次优先于排队批次，再次选择的文件属于后续批次；头像标明“本批 N 个文件”和“另有 N 批排队”，每批都沿用现有确认与取消边界。
- 状态边界：queued→等待发送；preparing 或尚未产生字节→待接收；有真实字节→发送中；整批字节到达总量但尚无成功终态→确认中；只有整批文件均收到成功结果才显示已发送，失败、取消、正在取消单独显示。preparing 包括发送前准备/等待阶段，当前公开 Core 事件不提供独立的“手机已接受”通知，不假设新增协议能力。进度环只使用当前批次字节，不把上一批的100%带入下一批，也不把单文件成功当整批成功。
- 任务中的设备即使临时不在发现列表仍保留头像与状态，禁止使用旧端口发起新发送；存在未被本轮发现的任务设备时，标题改为“传输设备”，不暗示其仍在附近。原生 outbox 清除后随之清除对应结果；其他设备和批次不会继承结果。发现开关关闭、服务错误和接收忙碌状态不显示为正在搜索。
- 保留现有原生批次协议、追加队列、结果/待发面板、通知确认、历史记录、取消与重试，不新增依赖、Provider、进程、网络请求或跨窗口消息。等待双点为静态提示，发送环采用真实确定进度，发现波纹继续复用独立 RepaintBoundary 与无障碍/离页停止规则。

验证：78 项相关 Flutter/Dart 测试通过（头像状态/高度/拖放、真实队列终态、页面/动画/视觉、outbox、原生批次与发送服务），11 个改动 Dart 文件 targeted analyze 无问题。已查看 Light/Dark 搜索、发送和成功渲染图；视觉 fixture 额外导出准备、确认、失败、取消及后续批次状态。`git diff --check` 通过，相关 Dart 文件均不超过500行。

人工回归：后续正常构建后，开启发现并检查搜索默认状态；对同一手机选择多文件，再在待接收/发送时追加下一批，确认每批一次手机确认、状态切换不残留上一批结果；检查不同手机排队、失败/取消、头像拖放、窄窗口滚动及设备消失后的旧端口禁用。本轮未启动或重建用户 App，自动测试不代表真实手机收发已验收。


## 发现端口共享与启动失败保真（2026-11-07）

- 问题证据：荣耀互联 `HonorConnect.app` 的 `HnOfficeCenter` 曾占用发现端口，旧 Core 的发现线程绑定失败后退出，但接收主进程仍等待连接，线程结果被忽略；页面将进程存活等同于正在搜索，最终没有设备也没有明确错误。这是发现启动问题，与手机选择不支持的直连接收模式独立。
- 私有 Core 0.3.6 尽力采用可共享的发现监听，并防止子进程继承发现句柄。对方允许共享时支持共同监听广播；对方独占端口时明确失败，不关闭第三方进程、不抢占 socket、不修改网络或权限。macOS 对同端口单播仍选择单一 socket，因此不承诺所有荣耀互联版本下都能同时发现；详细 socket/协议实现留在私有仓。
- TCP/UDP 监听失败分别通过公开 IPC `receive_port_in_use/discovery_port_in_use` 报告；运行中发现线程失败及时结束窗口。监听、广播准备及蓝牙启动完成后才发送 `discovery_ready`。生产 send/receive 能力依然为 false，IPC 仍为3，不涉及收发协议升级。
- 主仓 `HarmonyShareService.scanning` 必须等待真实就绪，启动时 `startingDiscovery` 显示“正在准备搜索…”。8秒无就绪报告 `discovery_start_timeout` 并有界停止进程，停止/配置/接收/离页清理对应计时器；异常结束不再每秒快速拉起。已有30秒网络健康轮询及手动重新扫描仍可恢复发现。
- 基础接收会话发现 stdout 静默关闭且无成功/错误终态时报告 `core_stopped`，不把异常退出当作正常结束；主动停止仍排空已经发出的真实终态。批次验证器允许转发新的就绪事件，既有批次确认、文件验证、通知和历史语义保持不变。
- 错误文案 zh/en 均明确指出发现端口/接收端口被占用、权限或广播不可用、启动超时/异常停止，并提供重新扫描建议。占用提示以荣耀互联为示例，不在未查询进程时断言占用者；技术详情保留公开错误信封。页面继续使用 Theme，发现背景高度与设备/批次展示不变，投屏和跨窗口协议不受影响。
- 制品固定到私有 commit `82e6cbd1fdbb34c443f00394ce2442ef007ced9b`，arm64 zip SHA-256 `89281e4724029f1a451e12f0cd2893a98ef2e339dc66318be35f3367d1f9ebd6`；正常 Debug/Profile/Release 构建通过既有安装阶段读取新锁。DFile helper 复用原锁定 zip 内经 manifest 摘要校验的未改动产物；新制品5成员摘要/签名、实际 Core0.3.6 / IPC3 hello 已验证。新锁的默认自动安装已在独立临时包结构验证，安装后5成员摘要和签名一致；本地私有 commit 尚未推送，当前机器使用已验证的相邻制品；其他机器的远端获取需先推送该私有提交。

验证：236项相关 Flutter/Dart 回归通过（nearby_share 全目录、页面/错误/头像/动画）；补充的准备状态与 Client 子集15项通过。16个相关 Dart 文件 targeted analyze 无问题；27项 Python 构建/安装/签名测试通过。私有原生51项库/IPC/进程回归通过，原有11项大文件/真机用例与隔离 launcher 仍为可选；`receiver_releases_children_port_and_staging_after_parent_exit` 因当前运行的旧 AnyDeck 独占发现端口，首次执行无法进入接收窗口而失败，后续定向运行明确排除，该接收父进程退出路径未完成本轮复验，未据此宣称完整原生测试全通过。

人工回归：正常重建后保持荣耀互联运行，检查双方设备发现；若对方独占端口，应出现占用原因且停止搜索动画。释放占用后点重新扫描，依次进入准备/搜索/发现设备；测试发送批次、手机来件与通知确认，确认新就绪状态不影响原流程。本轮未启动、重建、重签或重启用户正在运行的 AnyDeck，未向手机发送测试文件，真实荣耀互联共存与手机收发仍待验收。


## 设备头像点击区域收紧（2026-11-08）

- 问题：网格为完整批次状态预留高度后，将同样的紧约束传给头像，导致 Hover、点击与拖放区域延伸到名称下方的大块空白。
- 修复：网格 item 使用顶部对齐的 Align 释放子组件的高度约束，头像 Column 使用 MainAxisSize.min，命中与高亮区域随头像、名称、状态及批次信息的实际内容收紧。网格预留空间和396px发现区域保持原机制，状态变更及手机有无不会改变整块背景高度。
- 回归：新增空白区域点击不触发选择、名称点击仍可用、批次状态增高后仍仅保留10px底部内边距的真实命中测试；保留多语言、明暗主题、多设备、大字体与固定背景高度验证。视觉 fixture 导出 Light/Dark 的设备悬停图，确认高亮仅包裹内容。
- 验证：20项页面/头像/视觉测试与4个相关 Dart 文件 targeted analyze 通过，git diff --check 通过。本次只改布局约束，无新文案、Theme色、Provider、网络/进程或协议变更；未启动或重建用户 App，正常后续构建生效。


## 放开1 GiB文件限制以便手动测试（2026-11-08）

- 用户要求：先从代码中移除1 GiB大小限制，由用户自行测试真实大文件传输；本轮不自动向手机发送大文件或启动测试App。
- Flutter的选择快照、单文件/批次请求、接收声明、结果和逐文件/整批进度，与Core0.3.7及重新编译的DFile helper共同放开原1 GiB拦截。选择提示改为“一次选择1–100个普通非空文件”，不再提示每个不超过1 GiB；旧异常字符串仍可映射为当前本地化提示。
- 公开IPC仍为3，max_file_bytes/max_batch_bytes统一使用Dart VM/SQLite有符号64位可表示字节边界，这不是承诺支持该容量。批次不再通过“单文件上限×数量”限制总量，求和前检查剩余范围，防止整数回绕；数量、普通非空文件、路径/链接、大小/hash匹配、磁盘空间、30分钟超时与原子发布继续校验。
- 逐文件进度保持有界内存，超出可表示块序号或原有内存预算时仅停用该文件遥测，不截断计数或分配与文件大小成比例的无界内存。私有实现、固定依赖归档来源与底层固有容量边界记录在私有 docs/large-file-testing.md。
- 新制品固定到私有commit `133b9dbaa588c6a66fc980f77374461b7b899f97`，arm64 zip SHA-256 `8777094dad1b3a2a33c2fec01cdd116f4c627b3c7fb170d9d0090cb2ddc65dc3`。5成员hash/签名和实际Core0.3.7 / IPC3 hello的新版大小契约通过。私有提交仅本地保存，正常本机构建使用相邻已校验制品，跨机器远端获取前需推送私有提交。

验证：198项nearby_share回归、24项页面/错误回归、11个相关Dart文件targeted analyze通过；覆盖2 GiB稀疏文件只读取stat、5 GiB清单与进度、结果提交和总量溢出。52项原生库/IPC定向回归通过；上次已知受固定端口占用影响的接收父进程退出用例继续排除，保留原有可选真机/大文件ignored用例。DFile22项中20项通过、2项跳过（LAN真机与旧Git缓存补丁检查），包含ASan/UBSan、5 GiB元数据和小文件本地加密收发；未进行GiB真实文件数据传输。

交接：后续正常构建会同时更新Flutter代码与Core制品。用户自行尝试>1 GiB、>4 GiB单文件、混合批次与双向收发，并核对接收hash；失败时保留错误详情。字节100%仍需成功终态，本轮不声称手机大文件稳定性通过，不主动重建或重启当前AnyDeck。


## 手动 P2P 直连接收与网络恢复（2026-11-08，Core 0.3.8）

### 默认 LAN 与设置一致性

- 用户要求保留现有 LAN 收发，并在互传设置增加“高速传输模式”。`AppSettings.harmonyShareDirectMode` 与 `settings.harmonyShareDirectMode` 默认均为 false；旧配置不迁移成开启状态。开启表示允许本轮接收连接手机 WLAN，不会因发现手机或收到未认证请求而自动改网，也不代表已测得更高传输速率。
- 主窗口通过 `HarmonyShareService.configureDirectMode` 统一预留配置边界：空闲时停止旧接收窗口，保存成功后再重新读取配置并启动新窗口；保存失败重新读取原值，恢复原模式。服务关闭时只保存，不擅自启用接收。保存期间禁止文件选择、发送和并发设置；收发忙碌时 UI 禁用开关，Service 也拒绝变更，既有传输不会中途切模式。
- 子窗口通过 `change_harmony_share_direct_mode` 请求主窗口修改；`update_harmony_share_direct_mode` 只作为重载信号，各窗口重新读取已落盘的 bool，迟到广播不能用旧参数覆盖新值。子窗口不创建接收服务。每轮接收由 `ShareTransferMode.resolve()` 执行 SharedPreferences reload，避免复用旧缓存。
- IPC 仍为3；`receive_batch_interactive` 明确携带 `direct_mode=false/true`。旧 Core 未声明 `experimental.direct_mode=true` 时仍能走 LAN；用户开启直连后 Client 在启动前明确拒绝不支持的 Core，不静默切换网络或伪装正在搜索。本轮新增链路用于手机发到电脑，电脑发到手机保留既有 LAN 批次发送。

### 私有核心链路与凭据边界

- 直连模式按“BLE 控制通道认证 → 已认证的手机 WLAN 协商 → 连接手机 WLAN → BLE 中继续 metadata/端口协商 → 选定手机建立 Bytes/DFile 数据通道”推进，复用既有 Bytes/File、DFile、整批确认、真实进度、路径/hash 校验及原子发布语义。LAN 接收通路继续保留；不能将一次认证前的 BLE 写入视为允许切网。
- BLE relay 由私有 `share-discovery` 负责，固定首个合法会话对应的 central，后续报文继续通过既有生态认证状态机处理。metadata 与 Bytes/File 端口协商可保留在原 BLE 上，实际 TCP/数据连接限定选定手机地址并验证会话身份/密钥；Flutter 只接收通用批次与固定错误状态，不持有 BLE 协议报文或 Wi-Fi 凭据。
- Core 只从已认证的物理连接请求解析受限 SSID、passphrase、私有 IPv4 和超时。`share-network` 是与 Core 同目录的独立 Swift executable；凭据仅经匿名 stdin 的受限 JSON 传递，不写 argv、SharedPreferences、日志或制品。stdout 只输出必要地址及固定状态，未知 helper reason 收敛为固定错误，不能透传含凭据或系统路径的诊断文本。
- BLE 的 BasicInfo、通道握手、生态消息及 module21 封装已依据原版产物静态证据与离线 fixture 接入；直连模式不占用 LAN 固定发现/控制端口。若手机仍选择现有 LAN 地址，允许已认证 BLE 会话使用 LAN，不为此切换 Wi-Fi。模拟会话、编译通过和接口接线不等于原版手机已经完成 P2P 认证或收发；本轮没有真机 P2P 成功结论。

### Wi-Fi 权限、恢复与并发保护

- `share-network` 只使用公开 CoreWLAN / Keychain API。改变网卡前先确认当前网络可恢复；SSID 被系统隐藏而接口已有可用地址时明确要求定位/网络身份权限，不猜测原网络。原网络需要密码时仅支持可从用户或系统 Keychain 读取恢复凭据的个人 Wi-Fi；企业认证等不能可靠恢复的网络直接拒绝，用户可关闭高速模式继续 LAN。凭据只在 helper 内存中短期持有，不保存新的系统网络密码。
- 关联前后再次核对当前网络，用户已主动切换时不覆盖其选择。原本已连接目标网络时不重复关联或读取不必要的恢复凭据。接收成功、失败、取消、期限到达、stdin EOF 或直属父进程退出均进入同一恢复路径；恢复到原网络或原本未关联的状态，并等待网络身份确认。
- CoreWLAN 同步关联无法安全强制中断。join 超时或取消可先报告固定错误，helper 等已发起的关联返回后再恢复，避免迟到关联发生后无人负责恢复。恢复失败、仍在恢复、网络权限、其他直连占用等分别映射 zh/en 提示；网络恢复结果不能替代传输成功终态。
- 网络切换事件 `network_connecting/network_restoring` 只在来件已被接受后转发；`network_warning` 还必须属于固定的 `direct_network_restore_failed/pending`。数据已收齐并通过 hash/清单验证后先原子发布完整文件，再恢复原 Wi-Fi；恢复失败或尚未完成会发出该警告，仍输出 `batch_received`，避免将网络恢复异常变成已验证文件丢失。Service 保留成功记录、子文件与最近路径，同时持续显示恢复警告，接收窗口结束后不自动重开。zh/en 提示要求在系统 Wi-Fi 菜单检查并重连，并以下方互传记录确认文件接收结果；恢复警告不能把成功文件改写成失败，也不能让不完整批次提前成功。
- `NetworkOwnership` 在创建 CoreWLAN adapter 前取得 `/tmp/anydeck-share-network-<euid>.lock` 的非阻塞 `flock`。打开使用 `O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK`，只接受当前 uid、普通文件、单 link、0600，并核对锁定 fd 与可见路径的 inode；不修复或跟随可疑文件。锁文件不删除，防止新旧 inode 同时被锁；锁持续到 helper 恢复后退出，因此旧 Core 已超时返回时，新 Core 仍会收到 `direct_network_busy`，不会再次改网。
- Flutter 先向 Core 发送 SIGTERM，保留既有宽限期。强制回收 Core 的直接子进程前，仅用 `ps comm` 核对真实可执行路径，不读取 argv；只有与实际 Core 路径一致、同目录且为真实普通文件的 `share-network` 才保留恢复机会，收到 SIGTERM 并通过 Core 退出后的 EOF 继续恢复。其他同名程序、symlink、路径不匹配或非直属子进程不享有该豁免；不按名称全局扫描、关闭第三方 App 或取消其他用户进程。

### 六成员制品与验证边界

- Core 0.3.8 的严格原生成员集为 `anydeck-share-core`、`anydeck-dfile`、`share-discovery`、`share-network`、`libcrypto.3.dylib`、`libssl.3.dylib`，另含 `manifest.json`。构建脚本把新增 helper 纳入依赖检查、签名、摘要和 ZIP；主仓安装器继续验证锁定归档 hash、每成员 hash、总大小、manifest 架构、固定路径及链接边界，签名沿用制品构建及 App 嵌入验证链路。
- 新包必须同时包含六成员与完整 manifest。缺少 helper 的旧五成员包即使其余摘要正确也拒绝；完整新包可原子替换旧五成员运行布局，失败保留现有包。网络 helper 不从 PATH、外部脚本或其他 App 获取，版本锁与归档必须一同更新。
- 离线覆盖包含默认 LAN/开关持久化与跨窗口重载、busy/保存失败回退、旧 Core capability 门控、明确 IPC 模式、BLE 握手/module21 与 LAN TCP 状态机 fixture、匿名 stdin 与固定错误、join 超时后的 restore/EOF/reaper、Wi-Fi adapter 替身恢复、锁争用与不安全文件拒绝，以及六成员安装/升级/失败保留。直连就绪时显示“等待手机发送文件”，引导从手机分享面板选择本机，避免把等待来件显示成 LAN 搜索。最终验证与制品版本见下文。
- 本轮不启动、重启或操作用户 App，不连接真实手机、不切换实际 Wi-Fi。离线回归不等于真机 P2P 验收，也不代替定位/Keychain 授权、实际关联/DHCP、原网络恢复、荣耀互联共存或大文件验收；这些由用户在后续正常构建后手动测试。

人工回归顺序：先关闭高速模式验证既有 LAN 双向批次；再手动开启，验证手机发到电脑的 BLE 认证、手机 WLAN、接收确认与真实落盘。分别检查拒绝、等待期间取消、发送期间取消、Core 异常退出、恢复耗时和连续下一批；恢复尚未结束时再次发起应明确提示网络正忙。另测用户主动切换 Wi-Fi 后不被自动改回、权限不足或原网不可恢复时拒绝改网，以及关闭高速模式后恢复 LAN。真机成功仍以完整批次终态、实际文件和独立 hash 核对为准。

本轮验证：296项 Flutter 相关测试、30文件 analyze、26项安装器测试通过；私有 Core 的72项库测试、9项integration、39项Swift及12项显式非GiB批次/DFile/IPC回归通过。既有广播回环用例在本机环境连续超时，固定发现端口父进程退出用例因其他运行中App的占用未执行，均未计入通过数；没有为测试终止其他App或调整系统网络。arm64六成员制品的manifest哈希、架构、签名、实际hello、真实0.3.7五成员到0.3.8六成员隔离升级和增量不改写校验通过。

固定私有制品：commit `d0275ebfaed07e01c74e29a6145d90709584ae6d`，Core0.3.8/IPC3，zip SHA-256 `a27e1fbc7e7444ba93010d1155dc0274bdfd837ae16999e54916d69c7cafff92`。`experimental.direct_mode=true`仅表示实验代码已接入；生产send/receive仍为false。相邻私有zip和本机校验缓存可供常规构建使用，两个仓库均仅本地commit，未push。

直连启动允许尚无LAN IPv4：仅在检测器明确返回无可用地址时使用空地址进入BLE监听，真正数据地址仍由已确认的手机WLAN租约取得；默认LAN和其他检测异常保持失败提示，不伪造已有LAN。

恢复helper在数据成功后异常退出或EOF，同样归一为恢复失败告警；不会把helper内部原因传入仅允许两种恢复warning的Client校验器，避免文件已落盘却在界面被误报整批失败。此分支通过真实匿名helper pipe与事件收集回归，并经独立只读审阅确认。

真实进程清理夹具使用单调时钟的总启动期限并检查worker提前退出；启动失败会回收全部本轮PID、流订阅和目录。完整并行Flutter套件最终296项通过，避免重负载下过短夹具启动等待造成误报。

互传设置的高速传输开关与本机名称编辑器之间增加16px留白，避免开关的悬停背景紧贴输入框浮动标签。设置回归使用真实名称编辑器，在zh/en、Light/Dark窄窗口中检查两组控件的可见间距与布局；4项设置测试与2文件analyze通过，未启动项目。


## LAN 协商与有界回退（2026-11-08，Core 0.3.9）

### 需求与行为

- 默认仍为 LAN；只有用户手动开启高速传输模式，才允许已认证 BLE 会话建立 P2P Wi-Fi 租约。收到手机 P2P 请求，不再立即返回 `direct_mode_disabled`，也不自动改开关或切换电脑网络。
- 接收器将网络协商拆入独立文件。LAN 网络信息回复补充与当前本机 IPv4 对应的真实 SSID；只读 helper 不扫描猜测名称、不读取网络凭据、不改变关联。系统不提供名称时保持未知，不借用手机信息。Core/Swift 双重限时并回收超时或父进程退出后的读取进程。
- 已存在 TCP 控制连接时，先回复当前 LAN 地址继续协商，再只做一次网络重查；仅接受已认证的原 TCP 对端地址作为 LAN endpoint。未用于 LAN 的切网参数不再触发 P2P 专用解析失败。重复请求不延长 30 秒建链期限。
- 对端声明的 P2P 地址只作会话中的地址提示；数据 listener 与允许来源仍为实际 LAN 地址，后续仍验证会话密钥，不绑定/连接 P2P 地址、不添加路由或 IP 别名。数据通道建立后恢复原批次传输期限，避免把 30 秒建链上限套到大文件传输。
- 建链超时/对端断开统一报告 `lan_fallback_failed`；中英文说明已尝试 LAN、未建立数据连接及电脑未切 Wi-Fi，提供同局域网/路由隔离检查与重新分享建议。认证失败、取消等原因保留独立含义，不以 P2P 开关提示冒充实际失败原因。

### 验证与未完成边界

- Flutter 296 项相关回归与 3 文件 analyze、安装器 26 项通过。私有 Rust 81 unit + 10 integration 通过，另行启用的非 GiB 原生批次回归 12 项、Swift 40 项、制品构建脚本 1 项通过；快照新增非零退出断言后的 2 项 focused 通过。Rust 最终使用单线程并与构建顺序执行，避免并发启动触发快照/hello 的时限；既有本机广播回环用例仍未计入通过数，本次未改发现 socket 或系统防火墙。
- 新增加密控制帧/真实 TCP Bytes bind 回归覆盖默认/高速 TCP 回退、重复帧不延长、切网参数不影响 LAN、实际来源与密钥校验、错误 endpoint、BLE 未授权和 loopback 拒绝、只读快照安全边界与进程回收。
- 本轮获得用户授权并通过 HDC 操作 nova 12 Ultra，使用已有 128 B 测试文本，从手机发到电脑。手机和电脑当前在同一局域网，TCP 认证/来件确认成功，手机随后仍选择 P2P 地址并未建立 LAN 数据连接；**尚无真机 LAN 收件落盘/hash 成功证据，不能宣称手机接收问题已完全修好**。仅回复 LAN 地址、重查时序及网络信息补齐实验都未证明能强制该手机回退，未保留代用 SSID 等实验代码。测试中 AnyDeck 高速模式关闭，电脑 LAN 地址未变化。
- 用户明确：鸿蒙星河互联目前只确认能发现手机，未测试关闭高速传输时的接收。发现成功不等于 LAN 收件兼容。手机系统库/HAP 的 HDC 访问被系统拒绝，未绕过权限。后续仍需查明该手机系统的 LAN 模式协商兼容条件；手动高速/P2P 的真实 WLAN 关联、传输和恢复亦不能由离线回归代替。
- 固定制品：私有源码 `067b23d`（LAN 回退主体 `164fde8`），制品 commit `71310e9e3d4afac684f4177836b15535cc0cc95c`，Core0.3.9/IPC3，zip SHA-256 `ca436c7d236de8492ab5791c8c5217382a45dbe821cd472661d3e71dc603a9bf`。六成员摘要/arm64/严格签名、实际 hello、0.3.8→0.3.9 隔离升级和增量不改写通过。生产 send/receive capability 仍为 false；仅本地提交，未 push。

- 最终 Debug App 构建成功；包内六成员 hash/严格签名、实际 Core0.3.9 hello 及整个 App 的 deep/strict 签名校验通过。用户解锁 Mac 和手机后完成正式版本界面复测：高速模式实际为关闭，128 B 来件确认后进入传输，最终仍 0 B/128 B 失败；新 LAN 回退失败详情已在实际记录中验证。**LAN 收件兼容仍未通过，不能将本轮记为完整修复。**
- 补充选路字段的单变量真机对照无效，已撤回；原版相同字段的实际赋值与公开标准枚举存在语义差异，不能直接套用标准定义作为私有协议根因。手机侧受限日志未提供具体互传协商原因；缺少来源关联的系统发现错误未归因于 AnyDeck。
- 结束时已恢复正式 Core0.3.9，复验六成员 hash/整个 App deep/strict 签名；恢复 LAN 接收待机并再次发现手机。临时手机亮屏 override 已还原，实验代码和二进制均未保留。
