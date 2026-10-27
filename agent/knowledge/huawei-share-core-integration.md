# Huawei Share 私有核心集成边界

AnyDeck 主仓库仅保存 Flutter IPC 契约、制品锁定清单和安装脚本。协议解析、认证、Swift 广播、DFile 适配、协议测试及原生制品均归独立私有仓库 `solomanlove/AnyDeck-Share-Core`。主仓库当前本地分支已移除原 PoC 提交；推送前继续用 `git rev-list --objects origin/main..HEAD` 核验历史中没有 `tool/huawei_share_poc`。

## 构建链路

1. 私有仓库运行 `script/build_artifact.py`，输出按架构区分的 zip、包内 manifest、每文件 SHA-256；把 OpenSSL 3 动态库一起签名和打包。
2. 主仓库 `script/share_core.lock.json` 固定私有仓库 commit、IPC 版本与 zip SHA-256。
3. 构建 Release 时显式设置 `ANYDECK_SHARE_CORE=1`；`script/install_share_core.py`只读取锁定 commit 的制品，逐层校验后写入 `.app/Contents/MacOS/ShareCore/`，再由现有 `fix_macos_app_policy.sh` 签名整个 App。
4. `ShareCoreClient.probe()`通过 IPC version 1 握手，只信任显式声明的能力。无二进制或版本不符时失败；不使用外部 Python 或原星河进程。

## 当前验收与未完成项

- P0：私有仓库保留既有43项 Python 协议测试、11项 Swift 测试、DFile 本地双进程测试；Rust 新增有界封包、RSA/AES认证与离线握手测试。
- P1基础：arm64 私有制品可按固定 SHA-256 拉取、安装至隔离测试 App 并执行版本握手。主仓库二进制安装与能力解析测试通过。
- Rust IPC 声明 `discovery=true`、`send=false`、`receive=false`。CoAP 发现已有有界实现和离线测试；当前局域网真机未发现设备，BLE 广播、Bytes/File 通道与原生双向收发仍待迁移。不能启用生产传输入口，也不能将独立 PoC 的真机成绩转述为 Rust 核心真机验证。
- x86_64 制品、Developer ID签名与公证、Release 包内双向真机验收仍待完成。

当前集成不会替代 HDC 文件管理，也不与其设备身份自动合并。多窗口只应使用一个 Share Core 进程，后续状态通知需由主窗口统一分发。
