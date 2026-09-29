# Knowledge: adb-emulator-management（模拟器诊断与配置详情）

## 需求与入口

模拟器列表与设备管理为同级 Tab（索引 `-2`），主窗口和独立模拟器窗口共享 `EmulatorListPanel`。本次解决启动失败停留在橙色状态、双击详情入口不明显、配置只有原始 key 的问题。

## 启动与失败状态

- `EmulatorService.startEmulator` 返回 `EmulatorProcess`，以参数数组执行 `emulator -avd <name>`，不再使用无法获取输出与退出码的 detached 模式。进程创建成功仅表示启动请求开始，不代表设备已上线。
- `emulator_process.dart` 持续排空 stdout/stderr，各保留末尾 16,384 个字符；允许非标准 UTF-8 输出。进程退出后最多等待 2 秒收集尾部日志，随后取消流订阅。stderr 优先提供诊断，错误仅写入本地状态。
- `emulatorLaunchProvider` 按 AVD 名称保存启动阶段、进程存活状态、错误语义、日志和退出码；进程创建异常、上线前退出（包括退出码 0）、非零退出均显示错误。正常上线后退出码 0 对应正常关闭。
- 默认等待 ADB 上线 2 分钟，超时显示“进程仍在运行，请检查模拟器窗口”。继续观察后续上线或退出，不贸然终止用户模拟器；进程仍存活时禁止重复启动、清除数据及删除。确认退出后可再次启动，重试清除上次错误。
- 启动期间显式订阅 `runningEmulatorsProvider`，不因 Tab 卸载或 Riverpod 暂停而漏掉上线结果；所有启动完成或失败后释放该额外订阅。销毁 Provider 时取消计时器、关闭订阅，并忽略后续退出回调。
- 列表以红色错误图标与错误摘要替换橙色启动状态。摘要优先匹配 ERROR/PANIC/FATAL/Missing/Failed 等行，点击错误图标查看和复制包含退出码的完整有界日志；缺失 system image 的原始报错可以直接查看。
- 不自动安装 system image、不修改 AVD 配置。错误状态属于当前窗口 Isolate；另一窗口不会自动同步该次启动日志。切换 Tab 不终止用户启动的模拟器。

## 详情与配置说明

- 每行新增 info 图标与中英文 Tooltip，点击图标和双击行共用原有配置详情回调。
- 配置名列使用“本地化名称 + 原始 key”两行展示，配置值及复制内容仍保持原值。搜索同时匹配本地化名称、原始 key 和 value。
- `app_l10n_emulator_config.dart` 集中维护中英文释义，覆盖截图中的 AvdId、PlayStore、ABI、分区、快照和常见硬件、屏幕、传感器配置；未收录的扩展 key 显示“其他配置项”并保留原始 key，不猜测含义。
- `dashboard_emulator_layout.dart` 收口原有完整页面样式，`dashboard_emulator_error.dart` 负责错误展示；面板、表格和新增文件均控制在 500 行内。明暗主题、原有操作及独立窗口布局沿用已有机制。

## 验证与回归

- `flutter test --no-pub test/emulator_process_test.dart test/emulator_launch_test.dart test/emulator_panel_test.dart`：13 项全部通过，覆盖脚本模拟缺失镜像、真实退出码、stdout 错误、有界输出、安全参数传递、进程创建异常、退出前未上线、超时、重复启动防护、超时后上线恢复、无页面监听时状态更新及销毁后回调。
- Widget 测试覆盖红色错误入口、可复制诊断、详情图标、原始 key、中文/key/value 搜索、未知配置兜底，以及英文暗色配置显示；中英文文案 key 集合一致。
- 定向静态检查仅保留原有 `emulator_service.dart` 中列表读取的 `unawaited_return_in_try_block` 和 `dashboard_screen.dart` 的 unused import 两项警告；本次未修改它们。
- 不启动桌面项目或真实 AVD。待人工验证：点击缺少镜像的 AVD，确认失败后红色错误及日志；修复镜像后重试，检查上线状态、切换 Tab、正常关闭；在主窗口/独立窗口检查详情图标、双击与明暗主题。
