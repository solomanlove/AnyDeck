# iOS 进程管理

## 页面与实际能力

iOS 工作区的「进程管理」改为 Android 风格搜索工具栏和虚拟表格。默认「全部」，可选择用户进程、系统进程、仅显示应用，按名称、PID、所属应用类型及启动时间排序。搜索忽略大小写及首尾空格，覆盖名称、PID、进程/宿主 Bundle ID、执行路径。

- 名称和图标沿用 `IosProcessParser` 的完整安装路径关联以及 `IosIconService`、`IosAppIconView`；不按同名 Runner 或 `com.apple` 前缀猜归属。
- 用户/系统指关联的 `IosAppInfo.system`，不是 Android UID。未关联的条目不会被归入系统应用；`IsApplication=false` 标为非应用进程，其他未关联条目标为归属未知，都可在「全部」查看。
- 「仅应用」优先依据真实 `IsApplication`；字段缺失时才用明确的应用关联补充。扩展保留自身 Bundle ID，并单独展示/复制宿主 Bundle ID。
- 表格固定行高 60、`ListView.builder` 按需构建，最小宽度 1080，窄窗口水平滚动。复用 `DashboardTabLayout`、`DashboardSearchToolbar`、共享可排序表头与 `DashboardSnack`。
- 左键选择行，右键或行末菜单提供复制名称、PID、Bundle ID、宿主 Bundle ID、执行路径、详情与结束进程。详情复用原 `IosProcessTile`，保留版本、完整路径及启动时间。
- CPU%、CPU 时间、内存显示“未获取”，不能用 0、启动后时长或整机负载代替。未知指标不可排序。Go `time.Time` 零值（公元 1 年）同样视为未知启动时间。
- 文案独立放在 `app_l10n_ios_processes.dart` 并接入公共资源表；颜色来自主题，无 Android DEBUG、UID 等不适用字段。

## go-ios 能力核实（2026-10-06）

主机 `ios version` 返回 `1.2.0`，`ios ps --help` 支持 `ps [--apps]`。新页面执行不带 `--apps` 的全进程查询；旧 `IosCommandService.listProcesses` 兼容入口保持原状，页面不再调用该每次关联全量应用的方法。

官方 [`processList`](https://github.com/danielpaulus/go-ios/blob/v1.2.0/main.go#L1228) 在 `--apps` 为 true 时才按 `IsApplication` 过滤；不传时直接输出原始进程数组。该结论属于源码核实，实际设备可返回的进程范围仍需真机确认。

官方 v1.2.0 源码显示：

1. [`instruments_deviceinfo.go`](https://github.com/danielpaulus/go-ios/blob/v1.2.0/ios/instruments/instruments_deviceinfo.go) 的 `runningProcesses` 映射只有 `IsApplication / Name / Pid / RealAppName / StartDate`。
2. [`instruments_sysmontap.go`](https://github.com/danielpaulus/go-ios/blob/v1.2.0/ios/instruments/instruments_sysmontap.go) 虽配置 `procAttrs`、`physFootprint`，公开接收模型只映射整机 CPU 信息。
3. [`main.go` 的 `printSysmontapStats`](https://github.com/danielpaulus/go-ios/blob/v1.2.0/main.go#L523) 只输出 CPU 核数、时间戳和整机 `cpu_total_load`，没有 PID 级 CPU%、CPU 时间或内存结果。因此现有 CLI 不能给当前表格提供逐进程指标，本次不启动无收益的 sysmontap 后台采样。

本次 `ios list --details` 返回空列表，未能重新取得真机不带 `--apps` 的输出。此前 iOS 15.8.8 与 5 秒 sysmontap 无输出的信息属于前次记录，不作为本次真机验证或接口不支持的证据。后续若接入能返回逐 PID 数据的 DTX/helper，应先明确指标单位、采样区间、PID 生命周期和输出协议，再加有界采样及取消测试。

## 分层、缓存与生命周期

| 模块 | 职责 |
| --- | --- |
| `core/ios/ios_process_session.dart` | 页面专属 CLI 生命周期、双流消费、15 秒超时、8 MiB 输出上限、取消与 error/fatal 日志处理 |
| `core/ios/ios_process_service.dart` | 单 UDID 进程查询、5 分钟应用元数据缓存、手动更新元数据、结束前身份回读 |
| `features/ios/controller/ios_processes_controller.dart` | autoDispose family Notifier、最近成功快照、3 秒轮询、请求去重、图标请求取消 |
| `features/ios/model/ios_processes_filter.dart` | 搜索、分类、仅应用条件、真实字段排序与未知类型 |
| `features/ios/widgets/ios_processes_*.dart` | 无设备命令的工具栏与虚拟表格 |
| `features/ios/ios_processes_tab.dart` | 在线状态门控、复制、详情/结束弹窗与本地化反馈 |

命令参数以 `List<String>` 传给已有 `IosCommandService.start`，不拼接 shell：

```text
ios ps --udid=<UDID>
ios apps --all --udid=<UDID>
ios kill --pid=<PID> --udid=<UDID>
```

- 刷新完成后间隔 3 秒再查询，不使用会叠加慢命令的固定周期计时器；同一页面已有请求时，手动/自动刷新均不重入。取消自动刷新不打断当前短查询。
- 应用元数据首次、距上次尝试满 5 分钟或手动刷新时获取；失败也执行低频退避，保留旧关联并提示分类可能不完整。每 3 秒不会重查应用。
- 图标仅请求当前进程关联的宿主，复用内存/磁盘缓存；每个 Bundle ID 每次页面会话只尝试一次，失败不随轮询反复启动 helper。图标加载不阻塞进程列表。
- 查询失败保留上次可用进程，显示刷新失败状态；空 JSON 数组是有效空快照，仅日志或损坏 JSON 抛错。
- 页面的 `deviceOnlineProvider` 离线时卸载设备视图；切换设备按 UDID 重建视图。最后一个监听者离开后 autoDispose 取消 Timer、图标请求并关闭本会话所有主机 CLI。
- 处理 `Process.start` 尚未返回就取消的竞态：返回后立即终止 CLI。旧请求通过 Provider 生命周期检查，不能写入新设备状态。不会结束其他页面、概览或投屏的主机进程。

## 结束进程边界

1. 用户显式选择结束后显示名称/PID 确认弹窗，确认期间暂停自动刷新。
2. 确认后再读取目标 UDID 的全进程列表，对比 PID、名称、执行路径、启动时间；退出或字段变化时拒绝 kill。
3. 命令失败恢复 Loading 并反馈；成功后刷新列表。弹窗结束时恢复原自动刷新设置。
4. 确认期间离页、断线或切换设备，旧页面不能再发起结束操作。

身份回读属于尽力降低 PID 重用风险；回读与 kill 并非原子操作，缺失启动时间时识别能力受限。系统是否允许结束某个进程以 go-ios/设备实际响应为准。本次所有结束操作测试使用桩，未为验证结束任何真机进程。

## 验证与后续验收

```bash
flutter test --no-pub test/ios_process_service_test.dart test/ios_processes_filter_test.dart test/ios_processes_tab_test.dart test/ios_process_info_test.dart test/ios_processes_management_test.dart
```

31 项通过；涉及 15 个 Dart 文件的定向 `flutter analyze --no-pub` 无问题。覆盖：

- 真机格式字段、扩展宿主路径关联、旧字段兼容与 Go 零日期。
- 全进程参数、元数据缓存与失败保留、CLI 双流、超时、输出上限、取消未完成启动、PID 重用拦截。
- 用户/系统/全部与仅应用、名称/路径/PID/Bundle ID 搜索、数值排序、未知日期置底。
- 中英文 × 明暗主题的 420px 窗口、指标未知占位、1,000 行列表只构建可见行。
- 3 秒轮询不重入、图标去重、关刷新、断线取消、切换设备旧结果隔离、复制、取消/确认、失败恢复与确认中断线。

未启动桌面项目、未构建发布包，未完成本轮真机 UI 验收。待设备接入后只读检查 `ios ps` 与 `ios ps --apps` 的实际差异、系统/未知条目、图标、扩展、拔线/重连、连续刷新及两设备切换。真实结束能力仅在用户另行选择的可关闭进程上人工验收。
