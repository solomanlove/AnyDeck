# AnyDeck 内存与后台性能控制

## 目标与范围

设备切页、长时间日志输出、大文件导入、连续截图及历史设备切换时，控制进程数量、短期分配和常驻缓存。覆盖 Android ADB、HarmonyOS HDC、iOS go-ios、性能采样以及 macOS 原生 Texture 通知。

2026-11-07 按 P1 → P2 补齐同步 FFI、PID 辅助查询、静默刷新、iOS 页面生命周期、展示元数据缓存、截图保存和停帧通知的保护。本批验证只运行测试及静态检查，不启动 AnyDeck 应用。

## 数据与逻辑

| 流程 | 控制机制 | 生命周期边界 |
| --- | --- | --- |
| 性能采样（P1） | 每个可见性能页使用常驻 `PerformanceSampler` worker；FFI 库、指针和快照缓冲区只在 worker 内创建/释放；同一 worker 最多一次采样在途 | 切页/切设备立即使结果失效并请求关闭；快速返回先等待上一 worker 的 `stopped` 信号，避免积累原生查询；worker 在原生调用返回后清除设备增量缓存、释放缓冲区和端口；动态库不可用/worker 失败时回退原有 CLI |
| Direct ADB Socket（P1） | 从连接、握手、`read_exact` / `write_all` 到输出读取共用 2.5 秒整体 deadline；每次底层 IO 重新计算剩余时间；输出最多 1 MiB | 超时直接报错，不能把残缺快照当作成功；持续慢速输出也不能延长总时限 |
| Logcat / hilog | 会话序号丢弃迟到启动结果；实时日志和待刷新队列各最多 3000 行，单行最多 16384 字符；实时流也在分行阶段限长 | `IndexedStack` 中仅当前 Logcat Tab 采集；切页、切设备或销毁时终止进程 |
| Logcat PID 映射（P1） | 初次查询与实时采集解耦；每 5 秒尝试一次，已有查询时跳过；`CommandSession` 总时限 8 秒，stdout/stderr 合计最多 2 MiB | 停止、主采集退出或启动失败均取消辅助查询；迟到进程强杀，迟到映射按会话序号丢弃 |
| 文件日志导入 | `File.openRead` + UTF-8 文本流；按行限长，只保留最近 3000 条 | 导入完成后一次发布结果；Provider 销毁后不发布 |
| Android / HarmonyOS 终端 | stdout/stderr 100 ms 合批；待发布最多 128 块，每块最多 32768 字符；展示最多 1500 行，每行最多 16384 字符；历史最多 200 条 | 离开 Tab 时停止 shell 和在途 HDC 命令，保留输出；返回恢复；会话 ID/序号阻止迟到进程挂回 |
| 进程 / 网页静默刷新（P2） | 在途互斥与 Loading 分离，自动和手动刷新共用锁，断线不提前解锁；进程 Provider 仅 select 平台标记，避免 Registry 元数据更新重建查询；设备 ID 在发起时固定，旧轮次错误不弹到新页面 | 隐藏时停定时器，返回后恢复；全局页面也使用真实 `tabIndex` 判断可见性 |
| iOS syslog（P2） | 分行阶段最多 16384 字符；展示缓冲最多 3000 行/4 Mi 字符；待发布最多 1000 行/1 Mi 字符；100 ms 合批 | 隐藏/断线停止进程，返回时仅恢复先前由用户开始的采集；手动停止不自动恢复；启动和停止串行，迟到启动按序号强杀 |
| iOS 进程页（P2） | 隐藏时停止监听自动释放 Provider，取消轮询、图标请求和 CLI；保留页面本地筛选控件 | 返回时创建新的设备会话；旧 Future 不更新当前列表；只声明 `autoDispose` 不足以处理仍挂载的隐藏页面 |
| 连续截图（P2） | 自动截图和 PNG 保存处于同一在途链路，写完才排下一张；保存失败不增加计数；保存完成时检查请求及自动刷新轮次 | 切页失效在途结果和计数；已开始的单次文件写入完成后退出，不再积压后续 PNG；最后一个监听者离开后释放 `ui.Image` 和录屏资源 |
| iOS 设备发现 | 5 秒轮询有单次在途保护；CLI 回退 10 秒超时并杀进程 | Tracker 销毁后取消轮询，不再发布结果 |
| 应用包缓存 | 现有应用列表内存最多保留 12 个近期设备/连接 key | 历史完整快照仍兼容已有 SharedPreferences 版本键和格式 |
| 跨设备展示元数据（P2） | `PackageMetadataIndex` 使用 SQLite 磁盘索引，UI LRU/负缓存各最多 2048 项，待查询最多 128 项/批，负缓存 1 分钟；UI 缓存仅保留名称和图标路径 | 首屏仅打开索引，首次缺项时逐个迁移旧快照；JSON 解码、指纹计算、SQLite 和图标文件检查在 worker 中完成；Provider 销毁后不再通知 UI |
| macOS Texture（P2） | 使用已有 `anydeck_decoded_frames` 帧计数，帧序号未变化不调用 `textureFrameAvailable`；隐藏且没有录制时停 Timer | 窗口可见性通知恢复调度；隐藏录制维持 30 Hz 时间采样，静止画面不缩短录制时长；旧底座缺少帧计数符号时兼容原刷新方式 |

日志内存上限同时约束条数和单条长度；iOS syslog 额外约束字符总量。截图控制器按设备隔离，`autoDispose` 在最后一个监听者离开后执行，当前 `IndexedStack` 中的截图预览仍可保留。

## 元数据索引与兼容

- 数据库位置：Application Support 的 `apps/metadata.sqlite`；`metadata` 按旧快照 source + package 建主键，`imports` 保存快照 SHA-256 指纹。
- 保留 v3/v4 历史快照，逐个交给 worker 建立精简索引；快照指纹未变时跳过 JSON 解码。损坏的单个快照不阻断其余数据。
- 首次按需迁移前，对已被删除的历史 source 清理索引。查询优先当前设备，图标无效时回退其他有效来源。
- 图标缺失时在 worker 中探测确定文件名，避免在 Widget `build` 中同步枚举目录。解码失败由 `reportMissingIcon` 记录有界负结果并异步查找，默认图标继续可用。
- 每次迁移只持有一份历史 JSON 和解码结果；UI 不接收全历史包对象。完整应用快照仍使用原 SharedPreferences 持久化，SQLite 本次负责跨设备展示索引。
- 各窗口独立持有 LRU 和 worker；SQLite 使用 WAL 与 `busy_timeout` 协调多窗口访问。未新增跨窗口协议、可见文案或 Theme 配置。

## 核心实现入口

- `core/performance/performance_sampler.dart`、`rust_performance_bridge.dart`：worker、请求去重和 FFI 所有权。
- `rust/device_bridge/src/adb_socket.rs`：整体 deadline、输出上限及慢速 Socket 原生测试。
- `core/process/command_session.dart`、`core/logcat/logcat_pid_resolver.dart`：双流消费、进程取消与 PID 解析。
- `features/processes/processes_tab_refresh.dart`：共享静默/手动刷新锁，按现有 part 组织拆分，避免页面文件超过 500 行。
- `features/ios/ios_syslog_tab.dart`、`ios_processes_tab.dart`：隐藏生命周期；`core/logcat/bounded_log_buffer.dart` 统一日志预算。
- `core/apps/package_metadata_index.dart`、`package_metadata_resolver.dart`：SQLite 索引与有界 UI 缓存。
- `features/screenshot/controller/screenshot_auto_save_writer.dart`：可替换的保存 IO，用于慢磁盘背压测试。
- `macos/Runner/RustTexturePlugin.swift`：帧门控、隐藏/录制调度；`TextureFrameGate` 与 Flutter Engine 解耦测试。

## 测试与回归影响

直接影响性能页、Android/HarmonyOS 日志、进程页、网页调试、iOS 日志/进程页、应用图标和截图保存；投屏触控/键盘映射、设备物理屏幕恢复、明暗主题及多语言协议不改动。

自动测试覆盖：慢 FFI 主 Isolate 心跳、连续 await 不复用旧结果、worker 失败/超时/销毁后原生分配释放；慢 PID 查询不阻塞日志、不跨周期重入及异常退出回收；静默查询跨多个周期仍只有一次在途；iOS 隐藏恢复/手动停止/迟到启动与旧请求丢弃；日志多重预算；历史索引迁移/更新/删除/坏图标回退及 LRU/查询上限；慢 PNG 保存互斥和跨会话计数；停帧、隐藏及录制策略。

```bash
flutter analyze --no-pub
flutter test --no-pub
cargo test --manifest-path rust/device_bridge/Cargo.toml --lib
python3 test/native/run_memory_performance_tests.py
```

原生脚本使用临时目录编译 Rust/Swift 测试，Swift 直接编译当前 Texture 插件并调用实际调度策略，不创建窗口或 Flutter Engine。FFI 测试动态编译 C-ABI 桩，不再依赖硬编码真机序列号。

人工 Profile 验证路径（本批不启动应用）：

1. 打开 Android Logcat / HarmonyOS hilog，模拟 `ps` 慢于 5 秒；确认采集正常启动，PID 查询不重叠，切页/断线后无残留辅助进程。
2. 设备延迟/断线时打开性能页，确认窗口仍可滚动与操作；切设备后旧采样不更新图表；停止后观察原生缓冲区及 worker 数量。
3. iOS 日志与进程页反复切页；开始过的日志按意图恢复，手动停止后保持停止，隐藏期间不轮询。
4. 设置 1 秒自动截图并写慢目录；确认写入时不产生新的自动截图/保存，切页后旧保存不增加当前计数。
5. 浏览大量历史设备、缺失/损坏图标及使用记录，对比 GC 后 Heap、External、RSS 稳定值；查看索引重开和历史名称回读。
6. 投屏停帧、最小化、恢复及隐藏录制：确认停帧不反复标记 Texture 更新、恢复后显示最新帧，录制时长和音画状态正常。

单元测试和静态检查不能量化 macOS RSS、GPU Texture、CPU 节能收益或真实 ADB/HDC 链路峰值；这些由上述 Profile 路径验收。

## 2026-11-07 验证记录

- 本批 22 个相关测试文件共 100 项通过，覆盖新增保护以及原日志、终端、设备发现、iOS 管理、应用缓存、截图和网页调试回归。
- 最终把本批改动应用到独立 worktree 验证：上述 100 项测试全部通过，本批改动 Dart 文件静态检查为 0 问题；隔离全库检查与 HEAD 对照均为相同的 38 项既有 warning/info。
- Rust Device Bridge 全量单元测试：58 通过、1 项原有 ignored；原生独立脚本的 2 项 Socket 测试及 Swift Texture 调度测试通过。
- 全库 Flutter 回归执行结果：1388 通过、4 跳过、23 失败。对未包含本批改动的 HEAD `97ad1c2` 建立独立 worktree，运行相同失败文件：23 项失败全部重现，失败名称集合完全一致，无新增失败项。
- 既有失败分布：`harmony_tabs_and_wifi_test.dart` 分辨率解析 1 项、`brand_logo_helper_test.dart` 资源预期 4 项、`widget_test.dart` 旧界面断言 10 项、`app_pinyin_filter_test.dart` 1 项、`package_refresh_notifier_test.dart` 插件 mock 7 项。遵守局部修改原则，本批不调整这些既有功能或断言。
- 全库静态检查的既有 38 项 warning/info 在上述 HEAD 对照中也存在；工作区同时有其他功能的并行编辑，因此最终交付结论以隔离 worktree 的本批补丁验证为准，本批不加入无关风格清理。
- 本批未启动 AnyDeck 应用，未执行真机或 macOS RSS/GPU/CPU profiling，运行验收仍按上节路径执行。
