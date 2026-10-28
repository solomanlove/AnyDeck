# Huawei Share 私有核心集成边界

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
