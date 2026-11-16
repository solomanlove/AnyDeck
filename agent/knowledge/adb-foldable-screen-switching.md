# AnyDeck 折叠屏内外屏切换

## 目标与交互

- Android 整机投屏工具栏增加单个切屏按钮；默认自动，不持久化手动选择。
- 图标描述当前屏幕：内屏使用横向平板轮廓，外屏使用手机轮廓；自动模式增加 `A` 角标。
- 点击切到当前实际屏幕的另一面，此后点击内外往返；长按恢复自动。
- Tooltip 随模式、实际屏幕、切换目标和错误变化，中英文使用统一 l10n 表。
- 用户实际折叠/展开手机会取消手动请求，回到自动；停止、换线和关闭投屏同样释放请求。
- 仅 Android 整机投屏订阅能力；iOS、HarmonyOS、App 虚拟副屏没有此入口。

## 架构与代码落点

| 文件 | 职责 |
| --- | --- |
| `lib/core/foldable/foldable_screen_models.dart` | 物理屏角色、模式、能力、实际状态 |
| `lib/core/foldable/foldable_screen_parser.dart` | 运行时状态与双向布局解析 |
| `lib/core/foldable/foldable_screen_session.dart` | Helper 部署、JSON 协议、心跳、进程回收 |
| `lib/core/foldable/foldable_screen_service.dart` | 权限探测、状态请求、实际主屏确认及失败回滚 |
| `lib/core/foldable/foldable_screen_controller.dart` | Riverpod 状态、防连点、低频刷新和投屏生命周期 |
| `lib/app/window/mirror/widget/mirror_foldable_screen_button.dart` | 复用 `MirrorToolbarButton` 的图标、Tooltip 和 Toast |
| `tool/foldable_screen_helper/` | 设备侧请求所有权、排他锁、断连与心跳超时清理 |

没有新增依赖或全局持久化设置，也没有新增跨窗口 MethodChannel。Helper 的文件锁位于
物理手机上，因此能跨桌面 Isolate、USB/TCP transport 保证单会话控制。

## 能力探测与兼容边界

首次并行读取 `cmd device_state print-states`、`cmd device_state state`、
`dumpsys display` 和 `dumpsys package com.android.shell`；单条最多 4 秒。
只在以下证据齐全时返回 capability：

1. 恰好两块完整的 `INTERNAL/BUILT_IN`、`local:` 物理屏，排除虚拟屏和外接屏。
2. 运行时普通 OPEN/CLOSED 类状态具有两条不同的主屏映射：logical display 0 ON，另一屏 OFF。
3. 屏幕的显式 inner/outer/cover 名称与角色没有冲突。
4. Shell 具有 `android.permission.CONTROL_DEVICE_STATE`。

不使用厂商白名单，不把状态编号、逻辑 display ID 或面积大小当成通用内外屏规则。
TENT、HALF、REAR、CONCURRENT 等特殊状态不作为普通切换目标；三屏、缺失布局、
未知系统输出、权限缺失均隐藏入口。当前解析器识别 `DeviceStateToLayoutMap` 中
`StablePhysical{id=...}` 格式，其他厂商或新版输出格式需补 fixture 和适配后再开放。
Helper 明确报告 Hidden API/权限不支持后，本连接撤销能力并隐藏；临时失败保留已确认的入口供重试。

稳定期间每 3 秒只查询一次小型状态输出；committed state 改变才重新读 display dump。
普通手机探测结束后不常驻轮询；查询失败只在有效投屏期间重试。关闭、换线后丢弃迟到结果。

## 请求、确认与清理

主屏投屏继续采集 `display_id=0`。系统状态改变会重新绑定该逻辑屏对应的物理屏，
不能用 scrcpy 的 display 0/1 固定表示内/外屏。

设备侧以 `app_process` 运行独立 DEX JAR，调用 Hidden API
`DeviceStateManagerGlobal.requestState()`；不使用 system_server 的全局 Shell override。
制品按 SHA-256 命名，避免不同窗口覆盖正在使用的 JAR。

```text
探测 → 点击 → 确认无外部 override → Helper 握手/设备级锁
     → 请求目标状态 → 回读 committed/override/物理屏 ON/真实 logical0
     → 成功更新图标；失败关闭自身 Helper，释放请求并重新确认实际状态
```

- 使用 `FLAG_CANCEL_WHEN_BASE_CHANGES`，实际折叠变化会取消手动覆盖。
- 切换操作串行、防重复；切换前拦截录屏的启动/运行/停止状态和物理息屏状态。
- 切换期间录屏和物理息屏按钮禁用，避免尺寸变化破坏 MP4 或产生屏幕亮灭竞争。
- 请求确认预算为 8 秒，单条查询仍有独立超时；不能只以命令退出码 0 判定成功。
- 保留现有 socket、decoder、Texture；已有 Viewer 按新视频帧尺寸更新画面与触控，
  不为切屏新增整会话重启。
- 宿主每 3 秒发送 ping；stdin EOF、close、正常 shutdown、12 秒无心跳均主动 cancel。
- Helper 请求前、清理前核对 override PID；外部工具接管后不主动取消外部请求。
- Helper 退出和宿主进程销毁都有超时与强制终止兜底。

Android 的 cancel API 不携带 token，PID 查询与 cancel 间仍有外部抢占窗口。
设备侧 SIGKILL 不执行 finally/shutdown，部分系统允许 sticky request；不能承诺系统强杀时
必定恢复。不能对不明归属的残留请求无条件执行全局 reset。

## 验证与复现

```bash
python3 script/build_foldable_screen_helper.py
python3 tool/foldable_screen_helper/test_snapshot.py
flutter test --no-pub test/foldable_screen_parser_test.dart \
  test/foldable_screen_service_test.dart test/foldable_screen_session_test.dart \
  test/foldable_screen_controller_test.dart test/mirror_foldable_screen_button_test.dart
```

显式真机操作需要指定当前在线 transport；普通测试会跳过真机用例：

```bash
ANYDECK_FOLDABLE_DEVICE=DEVICE_ID flutter test --no-pub test/foldable_screen_device_test.dart
python3 tool/foldable_screen_helper/test_device.py --device DEVICE_ID --state STATE_ID
```

自动测试覆盖编号变化、逻辑主屏重绑定、特殊状态排除、未知能力隐藏、外部请求、
命令成功但主屏未变、物理屏 OFF、失败回滚、迟到工厂与请求、停止与重连轮询、
协议退出、自动/手动图标、中英文和明暗主题，以及真实工具栏的录屏/息屏互斥。
关联回归覆盖截图、几何与触控、窗口比例、通道恢复、快捷键和 iOS/HarmonyOS 工具栏。

2026-11-16 在 Samsung SM-F9710 完成真实 service 调用验收：

- 自动内屏 → 手动外屏 → 手动内屏 → 恢复自动全部通过。
- 对应截图尺寸为 `1248×1972`、`1848×2448`，未保存截图内容。
- 持有实际外屏请求后，stdin EOF 约 0.1 秒释放；停止心跳约 12.9 秒释放。
  两例均回到 committed=base OPENED，且没有 override 残留。
- 空请求握手、设备锁竞争、协议错误和 host 所有权解析均通过。

未启动或构建 AnyDeck 桌面 App；真实工具栏鼠标点击、原生窗口动画、视频连续性和触控
仍需桌面端人工验收。其他品牌目前没有真机验收结论，不将运行时字段识别等同于全品牌认证。
宿主 Flutter 3.50 / Dart 3.14；定向分析无新增 error/warning，全量分析存在仓库原有
5 条 warning 和 SDK 引入的 API 弃用 info，未进行无关修复或依赖升级。
