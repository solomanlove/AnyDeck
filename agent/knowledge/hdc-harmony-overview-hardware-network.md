# 鸿蒙设备概览：Wi-Fi、处理器与内核

## 数据来源

| 概览字段 | HDC shell 命令 | 解析规则 |
| --- | --- | --- |
| Wi-Fi | `hidumper -s WifiDevice` | 仅在 `WiFi connection status: connected` 时读取 `Connection.ssid`；不可读时保留已有的 IP 连通状态回退 |
| 处理器 | `param get const.product.model`、`nproc`、`param get const.product.cpu.abilist`、`uname -m` | 仅硬件型号 `ADA-AL00U` 补充 `Kirin 9000SL`；其他型号只展示实测 CPU 核心与架构 |
| 内核版本 | `uname -a` | 截去 `#` 后的构建编号与日期，保留内核名称和版本 |

## 实现边界

- 采集入口为 `deviceOverviewProvider` 的鸿蒙分支；命令并行执行，通过 `HdcService.shell` 的默认 15 秒超时保护。
- SSID 属于当前连接状态，不从已保存的 Wi-Fi 配置或宿主机网络推断。系统能力不可用时，只在 `wlan0` 有 IP 的情况下显示 `Connected`。
- 型号映射按精确硬件型号匹配，避免将 `nova 12 Ultra 星耀版` 等相近机型误写为 `Kirin 9000SL`。
- 在线刷新后写入既有 `DeviceOverview` 缓存；离线缓存仍可能反映上一次连接时的网络信息。
