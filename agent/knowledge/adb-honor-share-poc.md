# AnyDeck 荣耀文件互传

## 手机确认后发送立即失败修复（2026-11-17）

用户报告手机能看到接收弹窗，但点击接收后立即失败。实际发送记录保存 `FormatException: Unexpected batch event`；荣耀 Core 在用户确认后输出 `transfer_started(direction=send,total_bytes=声明大小)`，Flutter 的 `ShareBatchTransfer` 未识别该事件并停止 Core，数据尚未传出。

- 修复只在通用发送 Session 接受并校验该阶段事件的方向、整数类型和声明总量；不把它转换为字节进度或成功，仍以完整 `batch_sent` 终态完成。非法开始事件及未知事件继续拒绝并回收进程，旧 Huawei 不发送该事件时保持兼容。
- 新增独立 Session 用例，先在原代码重现同一异常，再验证开始→真实进度→终态、仅开始缺少终态、错误方向/大小/类型/缺字段和未知事件。49 项 Session、256 项 nearby_share 回归及 targeted analyze 通过；Debug 构建、整包严格签名和包内六成员 hash 通过。
- 用户在修复后的实际 App 重试同一个 1,421,800 B 视频，队列、实际字节和历史均成功，并确认手机目录可见且可播放。此为真实 UI 发送验收，不等同手机源 hash 已核验；随后回传失败在独立诊断中定位为 `honor_preview_type`，视频预览格式的接收兼容性继续单独处理。

本次发送修复不更换 Core 0.4.0 / IPC 3 制品，不新增协议源码、依赖、Provider、UI、l10n 或跨窗口方法。复验命令：`flutter test --no-pub test/core/nearby_share`；聚焦用例在 `share_transfer_started_session_cases.dart`。测试样本与本地诊断不进入 Git。

## Rust Core 与统一 UI（2026-11-10）

本轮需求为把荣耀分享接入私有 Rust Core，复用 AnyDeck 现有互传 UI，与华为/鸿蒙分享使用同一入口。Core 升级为 0.4.0 / IPC 3；页面和侧栏统一显示“文件互传”，同时发现、发送和接收两种协议。协议实现只在私有仓库，本仓库仅保存通用 IPC、UI 与记录模型。

- `ShareTransferProtocol` 白名单为 `huawei` / `honor`；旧事件和旧记录缺字段时默认 Huawei，显式未知值拒绝。设备 key、来件、队列、重试及历史均保留协议，同一 IP 不会覆盖另一种协议的设备。荣耀发送在启动前检查 Core 的 `experimental.honor` 能力。
- SQLite 原地补充 `protocol` 列，旧记录迁移为 Huawei；批次摘要和子记录沿用同一协议。发送继续使用既有选择/拖放、队列、真实进度、取消和历史，接收继续通过现有确认弹窗/系统通知；不增加独立品牌页面或第二套服务。
- 设备头像显示协议标签，帮助、通知及错误覆盖华为、荣耀和 AnyDeck 电脑；中英文和 Light/Dark 复用现有 l10n 与 Theme。沿用既有类名、Route、MethodChannel 和设置键，不作无关命名迁移。
- 统一接收器只向首个实际连接的协议移交唯一 stdin 确认器。高速模式继续沿用 Huawei BLE/P2P，荣耀保持 LAN，不自动切 Wi-Fi；BLE 启动失败仍遵循既有失败语义。发现端口被原荣耀互联占用时给出明确提示。
- Rust 运行不再依赖 Python、原荣耀互联 App 或本机安装制品。双架构制品继续使用原六成员 manifest、签名和 zip SHA-256 校验；IPC 版本仍为 3，生产 send/receive 能力仍为 false，荣耀通过实验能力单独声明。

本轮 Rust Core 对荣耀 Magic V6（Android 17/API 37）完成发送、手机实际目录独立读回及系统荣耀分享回传，1025 B 文本三份 SHA-256 一致。ADB 只用于设备定位、UI 操作和独立读回，不承载互传数据。该结果与下方历史 Python CLI PoC 分开计数。

自动回归覆盖协议白名单/旧制品门控、同 IP 双协议、历史迁移/重试、来件及明暗/双语 Widget；私有原生回归覆盖多文件 Unicode/长 emoji 文件名、拒绝、取消 ACK、KeepAlive、独立传输期限、无半批发布和子进程回收。各架构使用实际 Rust 与 native DFile 互操作，Huawei 桌面对传链路单独回归。命令与最终结果见 [集成边界](huawei-share-core-integration.md)。

Debug App 构建、整包签名/嵌入 Core 校验及实际统一入口、旧历史读取、双协议接收待机验证通过；接收开关已恢复开启。构建后的 UI 未另跑一轮手机收发，协议路由与确认由自动回归覆盖。当前真机验收限定这台 Magic V6 的 Rust Core 单文件；多文件和异常路径为自动互操作测试，Intel 在 Rosetta 执行，不等于所有荣耀机型/版本或实体 Intel Mac 均通过。荣耀账号绑定、可信设备、P2P 切网及大文件真机矩阵仍待扩充。私有实现与测试详见 `docs/honor-core-integration.md`。

## 历史 CLI PoC 结果（2026-11-10）

用户继续验证后，**单个1KiB文本的荣耀分享双向PoC已通过真机验收**，目标为荣耀Magic V6（Android17/API37）。协议实现仍只在私有Core仓库，尚未接入AnyDeck产品UI或发布新Core制品。

- Mac→手机：修正版独立CLI经手机确认后发送成功，手机文件管理器“荣耀分享”中可见测试文件；从实际接收目录独立读回1024B，SHA-256与本轮随机源文件一致。文件传输走荣耀分享，ADB仅用于定位设备、UI操作和独立落盘读回，手机未安装额外App。
- 手机→Mac：通过系统分享面板发给`AnyDeck Honor RX`，被动CCMP、DTCP预览、DFile及结束通知均完成；诊断运行和最终普通CLI各成功一次。源、手机读回、两份回传共四份文件的大小/hash均一致。
- 真机补齐四个差异：可选Airlink F3/F4及有界内部扩展；手机simple-auth能力是bitmask而非0/1枚举（本端仍关闭账号扩展）；sessionId绑定后返回无头像长度int32(0)，解除预览互等；previewOK和confirm分开发送并保留250ms状态完成窗口，受总期限/取消约束。
- 原版4秒完成释放窗口已经保留，本轮实际手机落盘通过；尚无对照实验证明旧文件缺失仅由该时序引起。250ms窗口解决了本机观测到的确认后断开，仍需更多机型验证。
- 本轮原荣耀互联进程未运行，独立收发通过；仍依赖本机固定版本安装制品的算法表，不等于可独立分发的Core。结束时测试CLI/helper均退出，TCP/UDP5700无监听；未改动原App配置。

私有代码与记录已提交`499c78e`（`codex/honor-share-poc`，前序`dd692d3`/`eac344e`）。本轮完整Python回归132项通过；native helper本轮未修改，前序独立目标9项通过、正常目标7项通过/1项可选环境跳过，本轮真实收发也经过helper完整成功终态。原始数据、系统APK、编译物和样本留在私有忽略目录，不进Git。

复现时重新确认当前LAN地址，发送生成新的1KiB源文件，再以该轮hash启动接收、在手机分享同一文件。详见私有`docs/honor-file-poc.md`及`docs/honor-dtcp-evidence.md`。后续产品化仍需解除安装制品依赖、荣耀adapter/UI和多版本、多文件/大文件、拒收/断线等真机验证。

## 需求与仓库边界

2026-11-09，用户要求先实现最小 PoC，目标为荣耀原生分享与 AnyDeck 的小文件互传。协议实现、逆向证据和自动测试放在相邻私有仓库 `AnyDeck-Share-Core`，不把协议源码或原始设备数据复制进本仓库。

本轮新增私有 CLI 探针，尚未集成 Flutter UI、替换制品或变更生产收发能力。实际入口、封包依据和后续交接在私有仓库 `docs/honor-poc.md`、`docs/honor-native-evidence.md`。

## 已验证与未完成

- 使用新随机身份发出荣耀格式的发现请求，实际荣耀手机在本轮 LAN 回复；通过 CoAP token 关联排除无关回复。广播及定向发现均收到响应。
- 独立程序连接手机控制端口成功，对端等待客户端握手。候选、连接事件始终声明未认证和未传输文件。
- 用户明确提供目标地址后，已对指定荣耀Magic V6重新验证定向发现和控制连接；早期另一LAN候选不计为目标手机验收。独立Hello首包获得CRC正确的加密回应。
- 随后已恢复加密回应及版本/RSA状态机，并对用户指定手机完成真实会话密钥协商和随机challenge回显校验；session-key只在内存，不输出密钥或明文。PoC明确关闭尚未实现的simple-auth账号扩展，不能把transport协商通过当成文件授权或可信身份绑定。
- 解密封装当前开发阶段仍需读取本机固定版本荣耀安装制品的算法表，不加载/执行原dylib；完全独立制品尚未交付。
- 基础阶段原版荣耀互联运行时已核对本机报文；后续本轮在原App进程未运行时已验证独立双向文件传输。
- 荣耀发现和控制封包均有别于现有 Huawei Core；同类 CoAP/密码学/DFile 工具可作为基础，但不能把现有握手直接发送给荣耀手机。
- 基础阶段尚未进入文件业务，后续真机落盘与双向hash结果以本页顶部为准。可以声明“指定Magic V6的单文件CLI PoC通过”，不得将其扩大为AnyDeck产品已全面支持荣耀文件互传。

## 测试与实现约束

CLI 限时运行、限频发包、限制报文和输出量、逐轮随机身份和token；所有退出路径关闭自己的socket，不终止原App、不修改Wi-Fi或系统权限。测试覆盖已知字节、非法输入、响应关联、端口选择和资源释放，并运行私有仓库既有Python协议回归。

本阶段私有实现提交 `eac344e`（分支 `codex/honor-share-poc`），87项Python协议回归通过，其中新增荣耀相关44项。真机仅验收发现、Hello、版本/RSA和会话密钥回显；flag2业务封装只有离线测试，不把它写成实际文件传输成功。

UI、多窗口、主题、国际化、投屏、ADB/HDC文件管理和现有互传IPC没有修改；后续只有真机收发验证成立后，才考虑增加独立荣耀adapter及产品入口。
