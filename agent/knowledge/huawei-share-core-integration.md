# Huawei Share 私有核心集成边界

当前基线：Core 0.2.1 / IPC 2，大文件实验上限 1 GiB 已完成离线验证，生产能力仍未发布。最新证据与限制见本文末尾及 `docs/plans/harmony-share-delivery.md`；早期 1 MiB 与 IPC 1 段落保留为实施历史。

AnyDeck 主仓库仅保存 Flutter IPC 契约、制品锁定清单和安装脚本。协议解析、认证、Swift 广播、DFile 适配、协议测试及原生制品均归独立私有仓库 `solomanlove/AnyDeck-Share-Core`。主仓库当前 `main` 与 `origin/main` 不可达原 PoC 对象；推送前继续用 `git rev-list --objects origin/main..HEAD` 核验历史中没有 `tool/huawei_share_poc`。本机 Codex checkpoint 仍保留旧树，仅属于本地内部引用，不随 `main` 推送。

## 构建链路

1. 私有仓库运行 `script/build_artifact.py`，输出按架构区分的 zip、包内 manifest、每文件 SHA-256；把 Swift BLE helper、DFile helper 和 OpenSSL 3 动态库一起签名和打包。
2. 主仓库 `script/share_core.lock.json` 固定私有仓库 commit、IPC 版本与 zip SHA-256。
3. 构建 Release 时显式设置 `ANYDECK_SHARE_CORE=1`；`script/install_share_core.py`只读取锁定 commit 的制品，逐层校验后写入 `.app/Contents/MacOS/ShareCore/`，再由现有 `fix_macos_app_policy.sh` 签名整个 App。
4. `ShareCoreClient.probe()`通过 IPC version 1 握手，只信任显式声明的能力。无二进制或版本不符时失败；不使用外部 Python 或原星河进程。

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
