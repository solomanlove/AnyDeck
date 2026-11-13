# AnyDeck 局域网投屏接收端命名

## 需求与使用规则

同一局域网运行多台 AnyDeck 时，用户需要从手机投屏列表直接辨认目标电脑。

- AirPlay 默认 `AnyDeck-电脑名称-AirPlay`，DLNA 默认 `AnyDeck-电脑名称-DLNA`。
- macOS 优先读取系统 `ComputerName`，不可读时尝试 hostname；仍无有效名称时使用 `Mac/PC-稳定短码`。
- 保留已有自定义名称，包括 `AnyDeck-AirPlay-FKW` 等历史手动名称，不通过前缀或正则猜测其是否为默认名。
- 空白值以及旧固定默认值 `AnyDeck-AirPlay`、`AnyDeck-DLNA`、`AnyDeck DLNA` 自动迁移。记录上次生成的默认名称，后续系统电脑改名仅更新自动名称。
- 设置页及投屏接收页的清空、恢复默认操作都使用本机动态默认名称。
- 启动前发现其他接收端重名时，在协议前追加固定短码，例如 `AnyDeck-办公室 Mac-A7B2C3-AirPlay`。自定义名称没有协议后缀时，在末尾追加短码；原始自定义设置不变。
- 投屏接收页顶部展示本机两个协议的名称并支持选择复制。服务运行时展示会话/服务正在使用的名称，停止时展示配置名称。活跃 AirPlay 会话改名不会立即重启，页面继续显示当前会话名。

## 身份、持久化与职责

| 入口或键 | 职责 |
| --- | --- |
| `lib/core/receiver/receiver_identity.dart` | 读取系统电脑名；创建并保存随机 UUID v4，前 6 个十六进制字符作为稳定短码；不读取硬件序列号或 MAC |
| `settings.receiverIdentityUuid` | 安装身份，重启和改名保持不变；清除应用配置后会重新生成 |
| `lib/core/receiver/receiver_names.dart` | 默认名生成、UTF-8 截断、旧值迁移、追加短码与冲突记录 |
| `settings.receiverAutoName.AirPlay/DLNA` | 上一次自动生成的名称，用于区分自动模式与自定义模式 |
| `settings.receiverNameConflicts` | 发生过冲突的协议与原始名称，持久保留，避免对端暂时离线后本机名称反复变化 |
| `settings.airplayServerName` / `settings.dlnaServerName` | 沿用既有设置键；存储当前自动名或原始自定义名 |
| `app_settings_receiver_names.dart` | 统一初始化、主窗口写入、跨窗口快照、启动前名称解析 |
| `receiver_local_names.dart` | 根据服务会话和设置展示本机名称，复用 Theme 与双语文案 |

自动名称不超过 50 个 UTF-8 字节，为 RAOP 服务实例的 12 位设备 ID 与 `@` 前缀保留空间；截断只发生在完整 Unicode 码点边界，并保留 `AnyDeck-` 与协议后缀。用户已有自定义名称沿用既有边界，不静默截断；发生冲突所生成的广播名遵守相同字节限制。

DLNA 生产实例使用安装 UUID 作为 UDN；device.xml、SSDP Search Target、USN、存活/离线通知与 SID 统一使用该实例身份。以前所有电脑共用的固定 UUID 仅保留为纯协议 helper 和测试兼容默认值，不再用于生产广播，避免手机把两台不同电脑合并。

## 重名探测与生命周期

- AirPlay 使用 macOS 系统 `/usr/bin/dns-sd -B _airplay._tcp local.` 进行短时浏览，精确匹配实例名称。命令通过参数数组启动，输出有界，结束或超时后终止并回收进程。
- DLNA 从临时 UDP socket 发出 SSDP M-SEARCH，收集有限数量的 MediaRenderer 应答，排除本实例 UUID，再有界并行读取应答者的 device.xml 比较 friendlyName。HTTP 仅访问应答者的本地 IPv4 地址，不跟随跳转，限制描述大小与超时，拒绝 DTD。
- 只在准备启用服务或运行中改为新名称时探测，不在设置加载或 Widget build 中扫描，不新增常驻进程。已有短码或已有冲突记录可直接复用。
- 探测期间用户修改了名称，启动前重新解析最新设置；名称编辑组件等待保存完成再重启空闲 AirPlay 广播，并防止失焦/提交重复保存。
- 仅主窗口首次生成身份与写入名称。子窗口通过 `resolve_receiver_names` 读取快照、`change_receiver_name` 请求修改，主窗口以 `update_receiver_names` 同步当前名称及两个动态默认值。

有界探测属于尽力发现，不提供分布式名称锁。网络未响应、权限受限或两台电脑同时启动时可能漏检；Bonjour 仍可能执行自身的自动重命名，当前 native callback 尚未回传最终发布名称。此边界需要两台电脑真实局域网验收，不将 mock 或 loopback 测试等同于手机端验收。

## 验证与回归

自动验证入口：

```bash
flutter test --no-pub test/core/receiver test/receiver_name_settings_test.dart test/app_settings_test.dart test/receiver_name_setting_field_test.dart test/receiver_dashboard_tab_test.dart test/core/dlna
flutter analyze --no-pub
git diff --check
```

测试覆盖身份持久化与改名、电脑名读取失败、中文/emoji 字节边界、旧默认迁移、自定义保留、重名持久化、异步初始化与编辑竞争、主子窗口名称请求、网络探测 parser/超时、同名 DLNA 实例的独立身份，以及双语、明暗主题、窄窗口长名称和实际会话名展示。

2026-11-13 自动验证记录：名称与探测 23 项、DLNA 19 项、接收页/编辑组件 11 项、关联设置与快捷键回归 29 项，共 82 项通过。18 个相关入口的定向 `flutter analyze --no-pub` 无问题；全仓检查仍有无关既有文件的 lint 提示（48 项，无 error），本次未扩改这些文件。`git diff --check` 通过。

人工回归：

1. 两台不同电脑名的 Mac 同时启用两种协议，手机列表名称与本机页面一致。
2. 将两台系统电脑名称设置相同，先后启动接收，后启动端追加稳定短码；重启后短码保持不变。
3. 两台设置相同自定义名，确认实际广播名追加短码且原始自定义设置保留。
4. 正在 AirPlay 镜像或播放视频时改名，当前连接不中断，页面显示当前使用名，下一次启用使用新名。
5. DLNA 播放期间改名不停止媒体，两台同名接收端仍拥有不同 UDN；手机缓存旧列表时重新搜索。
6. 检查两个窗口的名称及恢复默认一致；切换中英文、明暗主题与窄窗口后长名称可读。

本次按要求不启动项目或进行真机投屏，以上人工项尚未验收；自动验证结果以提交前执行记录为准。
