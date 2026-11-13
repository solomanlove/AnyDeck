# AnyDeck 局域网投屏接收端命名

## 需求与使用规则

同一局域网运行多台 AnyDeck 时，用户需要从手机投屏列表直接辨认目标电脑。

- AirPlay 默认 `AnyDeck-电脑名称-AirPlay`，DLNA 默认 `AnyDeck-电脑名称-DLNA`。
- macOS 优先读取系统 `ComputerName`，不可读时尝试 hostname；仍无有效名称时使用 `Mac/PC-稳定短码`。
- 保留已有自定义名称，包括 `AnyDeck-AirPlay-FKW` 等历史手动名称，不通过前缀或正则猜测其是否为默认名。
- 空白值以及旧固定默认值 `AnyDeck-AirPlay`、`AnyDeck-DLNA`、`AnyDeck DLNA` 自动迁移。记录上次生成的默认名称，后续系统电脑改名仅更新自动名称。
- 设置页及投屏接收页的清空、恢复默认操作都使用本机动态默认名称。
- 启动前或运行中发现其他接收端重名时，在协议前追加固定短码，例如 `AnyDeck-办公室 Mac-A7B2C3-AirPlay`。自定义名称没有协议后缀时，在末尾追加短码；原始自定义设置不变。短码前缀仍冲突时有限升级为 12 位、32 位，不反复拼接或随重启降级。
- 投屏接收页不再显示顶部“本机投屏名称”面板，名称集中在各协议卡片。实际广播名与配置不同时，在该卡片内紧凑显示可复制的“当前广播名称”；未确认发布时只提示“正在确认名称”，不将请求名称冒充成功广播名。活跃 AirPlay 会话改配置不立即重启，继续展示当前已确认会话名。

## 身份、持久化与职责

| 入口或键 | 职责 |
| --- | --- |
| `lib/core/receiver/receiver_identity.dart` | 读取系统电脑名；创建并保存随机 UUID v4，前 6 个十六进制字符作为稳定短码；不读取硬件序列号或 MAC |
| `settings.receiverIdentityUuid` | 安装身份，重启和改名保持不变；清除应用配置后会重新生成 |
| `lib/core/receiver/receiver_names.dart` | 默认名生成、UTF-8 截断、旧值迁移、追加短码与冲突记录 |
| `settings.receiverAutoName.AirPlay/DLNA` | 上一次自动生成的名称，用于区分自动模式与自定义模式 |
| `settings.receiverNameConflicts` | 发生过冲突的协议与原始名称，持久保留，避免对端暂时离线后本机名称反复变化 |
| `settings.receiverNameCodeLengths` | 记录原始名称已升级的短码长度；同时回写自动名称 root key 和原始自定义 key，避免多次异步回调或预探测后的名称降级 |
| `settings.airplayServerName` / `settings.dlnaServerName` | 沿用既有设置键；存储当前自动名或原始自定义名 |
| `app_settings_receiver_names.dart` | 统一初始化、主窗口写入、跨窗口快照、启动前名称解析 |
| `receiver_name_section.dart` | 各协议卡片内展示配置、实际广播名或待确认状态，复用 Theme 与双语文案 |
| `native/uxplay_publication.h`、`vendor/uxplay/lib/dnssd.*` | DNS-SD 异步注册确认、稳定后备名和运行时冲突重注册 |
| `airplay_publication.dart`、`AirPlaySessionData.isPublished` | 等待和轮询 native 真实发布状态，接收确认名称并驱动 UI |
| `dlna_name_conflict_monitor.dart`、`dlna_renderer_conflicts.dart` | 复用 SSDP socket 观察运行时重名、有限补搜、同源后备名识别和迟到结果隔离 |

自动名称不超过 50 个 UTF-8 字节，为 RAOP 服务实例的 12 位设备 ID 与 `@` 前缀保留空间；截断只发生在完整 Unicode 码点边界，并保留 `AnyDeck-` 与协议后缀。用户已有自定义名称沿用既有边界，不静默截断；发生冲突所生成的广播名遵守相同字节限制。

DLNA 生产实例使用安装 UUID 作为 UDN；device.xml、SSDP Search Target、USN、存活/离线通知与 SID 统一使用该实例身份。以前所有电脑共用的固定 UUID 仅保留为纯协议 helper 和测试兼容默认值，不再用于生产广播，避免手机把两台不同电脑合并。

## 重名探测与生命周期

- 启动前保留已有 `/usr/bin/dns-sd` 短时浏览和临时 UDP M-SEARCH，作为避免冲突的优化，不再依赖它保证同时启动的名称消歧。
- AirPlay 的 DNSServiceRegister 开启 `NoAutoRename`，等待 RAOP/AirPlay 两条记录的异步成功回调后才报告已发布。`NameConflict` 或意外自动改名会触发 6→12→32 位稳定名称升级；在 DNSServiceProcessResult 返回后替换发现记录，避免回调内释放正在处理的 sdRef。完整身份仍冲突则明确失败，不生成 `(2)` 或虚假成功状态。
- native `/info` 与发布状态共用不可变名称字符串和原子索引；运行中重注册只替换 DNSServiceRef，不销毁 listener、密钥、媒体或活跃连接。TXT buffer 在重注册期间复用，全部协议线程退出后统一释放，避免 `/info` 并发读取 UAF。
- Dart 启动等待 native 确认名称，并复用既有状态轮询同步晚到冲突；同一次注册的短码升级持久回写原始名称，视频窗口标题同步更新。新 ABI 为 `anydeck_airplay_start_with_fallbacks`、`anydeck_airplay_publication_status`、`anydeck_airplay_copy_published_name`，旧动态库缺符号时明确要求更新。
- DLNA 在现有 1900 socket 接收 NOTIFY alive/update 和 M-SEARCH 应答，排除本 UUID，有界查询 device.xml；既匹配原名，也识别对端已加自身短码的同源名称，解决“第一台先改名、第二台才读取描述”的竞态。前 6/12 位相同的 UUID 直接选择能区分两者的长度。
- DLNA 启用后立即搜索，并在 1 秒、3 秒有限补搜；运行中每 60 秒重查、补加入新网卡并重发 alive。描述查询最多 2 个并发、32 项缓存、64 KiB、1 秒；仅访问应答者本地 IPv4 地址，不跟随跳转，拒绝 DTD，不新增常驻 socket 或 CLI。
- DLNA 只更新发现名和播放器标题；重名、用户改名和 stop 使用 generation 与原始名校验，迟到 HTTP 结果不能覆盖新设置或重启已停止的服务。标题同步失败不停止媒体，也不阻断实际发现名与 UI 刷新。
- 探测期间用户修改了名称，启动前重新解析最新设置；名称编辑组件等待保存完成再重启空闲 AirPlay 广播，并防止失焦/提交重复保存。
- 仅主窗口首次生成身份与写入名称。子窗口通过 `resolve_receiver_names` 读取快照、`change_receiver_name` 请求修改，主窗口以 `update_receiver_names` 同步当前名称及两个动态默认值。

同时启动不再依赖一次有界预探测：AirPlay 由 Bonjour 注册冲突回调收敛，DLNA 由运行公告、补搜与同源短码识别收敛。网络完全隔离或手机缓存旧列表仍受各端发现行为限制；真实 Bonjour 双实例验证不等同于两台物理电脑加手机端整体验收。

## 验证与回归

自动验证入口：

```bash
flutter test --no-pub test/core/receiver test/receiver_name_settings_test.dart test/app_settings_test.dart test/receiver_name_setting_field_test.dart test/receiver_dashboard_tab_test.dart test/core/dlna
flutter analyze --no-pub
git diff --check
```

测试覆盖身份持久化与改名、电脑名读取失败、中文/emoji 字节边界、旧默认迁移、自定义保留、重名持久化、异步初始化与编辑竞争、主子窗口名称请求、网络探测 parser/超时、同名 DLNA 实例的独立身份，以及双语、明暗主题、窄窗口长名称和实际会话名展示。

2026-11-13 自动验证记录：名称与探测 23 项、DLNA 19 项、接收页/编辑组件 11 项、关联设置与快捷键回归 29 项，共 82 项通过。18 个相关入口的定向 `flutter analyze --no-pub` 无问题；全仓检查仍有无关既有文件的 lint 提示（48 项，无 error），本次未扩改这些文件。`git diff --check` 通过。

同日后续验证：名称、DLNA 与设置 58 项，AirPlay、UI 与关联回归 65 项通过；额外使用本机构建的 debug dylib 运行 2 项真实 native FFI/Bonjour 测试，通过同名并发注册、实际发布名回读及后备名重启稳定性。C DNS-SD harness 在 UBSan 下覆盖同时注册、晚到冲突、6/12/32 升级、意外 `(2)`、最终失败与 TXT 生命周期；Cargo UxPlay 5 项 loopback 测试通过。相关静态检查无问题，全仓当前保留 38 项既有 lint（无 error）。

额外验证命令：

```bash
clang -std=gnu11 -g -fsanitize=undefined -I rust/device_bridge/vendor/uxplay/lib test/native/airplay_dnssd_registration_test.c rust/device_bridge/vendor/uxplay/lib/utils.c -o /tmp/anydeck-airplay-dnssd-test
/tmp/anydeck-airplay-dnssd-test
cargo test --manifest-path rust/device_bridge/Cargo.toml --lib airplay::uxplay --no-fail-fast
cargo build --manifest-path rust/device_bridge/Cargo.toml --lib
ANYDECK_DEVICE_BRIDGE="$PWD/rust/device_bridge/target/debug/libanydeck_device_bridge.dylib" flutter test --no-pub test/airplay_native_integration_test.dart
```

人工回归：

1. 两台不同电脑名的 Mac 同时启用两种协议，手机列表名称与本机页面一致。
2. 将两台系统电脑名称设置相同，同时启动接收，确认由异步注册/运行观察自动加入稳定短码；重启后短码及升级长度保持不变。
3. 两台设置相同自定义名，确认实际广播名追加短码且原始自定义设置保留。
4. 正在 AirPlay 镜像或播放视频时改名，当前连接不中断，页面显示当前使用名，下一次启用使用新名。
5. DLNA 播放期间改名不停止媒体，两台同名接收端仍拥有不同 UDN；手机缓存旧列表时重新搜索。
6. 检查两个窗口的名称及恢复默认一致；切换中英文、明暗主题与窄窗口后长名称可读。

本次未启动 Flutter App 或进行真机投屏；执行了独立 native/Bonjour 与 loopback 测试，以上物理多机人工项尚未验收。
