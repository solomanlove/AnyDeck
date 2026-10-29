# ADB 截图录屏与布局分析合并架构指南 (adb-screenshot-layout-merge)

## 1. 概述与设计背景

为了提升 AnyDeck 桌面端在多设备调试下的操作流畅度，避免两套重复的截图画布与工具栏，本项目将原有的“截图录屏”与“布局分析”两大功能收口为一个统一的工作台：
- **入口收口**：左侧主导航栏移除独立的“布局分析”（原 Tab 8），仅保留“截图录屏”（Tab 9）。历史代码或通知中发往 Tab 8 的选中请求在 `ToolTabNotifier` 中自动归一化映射为 Tab 9。
- **模式切换**：在顶部统一工具栏的右侧增加“布局分析”开关（仅 Android 设备展示，iOS 与 HarmonyOS 自动隐藏）。
- **动静结合**：开启布局分析后，工作区自适应展开为三栏结构（左侧控件树、中间共享截图画布、右侧属性面板），并原子化并发抓取最新截图与 XML 控件树；关闭后收起左右面板，恢复普通截图与录屏功能，且保留当前画面。
- **轻量解耦**：所有新增与重构代码严格遵循单一文件 `<= 500 行` 规范，UI 与控制逻辑分离，关键流程配备中文注释。

---

## 2. 架构设计与目录结构

合并后的截图与布局分析模块收口在 `lib/features/screenshot/`，结构如下：

```text
lib/features/screenshot/
├── dashboard_screenshot_tab.dart         # 主容器（处理三栏展开与单画布切换）
├── dashboard_screenshot_recording.dart   # 录屏脉冲红点与时长格式化共享组件
├── model/
│   └── screenshot_state.dart             # 统一状态模型与 ScreenRecordPhase 枚举
├── controller/
│   ├── screenshot_controller.dart        # 核心 Riverpod Notifier（并发拉取、原子刷新与请求失效）
│   ├── screenshot_record_runner.dart     # 跨平台（ADB/HDC/Scrcpy）录屏子进程执行器
│   └── screenshot_export_helper.dart     # 单图保存、剪贴板复制、PNG+XML 打包导出工具
└── widgets/
    ├── screenshot_canvas.dart            # 共享交互式画布（平移、缩放、自适应居中与坐标映射）
    ├── screen_preview_painter.dart       # 截图渲染与布局边界、高亮、尺寸标注 CustomPainter
    ├── screenshot_toolbar.dart           # 顶部工具栏（操作按钮与布局分析开关）
    └── screenshot_bottom_bar.dart        # 底栏（缩放操作与 PNG 尺寸、格式、大小）
```

---

## 3. 核心机制与状态模型

### 3.1 录屏 5 阶段状态机 (`ScreenRecordPhase`)

为了防止录屏过程中的文件写入冲突或死锁，录屏生命周期抽象为 5 个原子阶段：
```dart
enum ScreenRecordPhase {
  idle,       // 空闲
  starting,   // 正在启动录制（拉起 adb/hdc screenrecord）
  recording,  // 正在录制中（计时器工作）
  stopping,   // 正在停止录制（发送 SIGINT / Ctrl+C）
  saving,     // 正在从设备拉取视频文件到本地
}
```

**互斥逻辑**：
- 只要 `recordPhase != ScreenRecordPhase.idle`（即处于启动、录屏、停止、保存任一活跃阶段），`canToggleLayoutAnalysis` 计算属性即返回 `false`。
- 顶部工具栏中的布局分析 `CupertinoSwitch` 置灰禁用，并在 Tooltip 中动态给出对应阶段的本地化提示（例如 `recordingDisableLayoutAnalysis`、`recordingSavingDisableLayout` 等）。
- 开启布局分析期间，录屏按钮与连续截图功能直接禁用。

### 3.2 原子化并发刷新与请求失效令牌 (`_requestId`)

在布局分析模式下，截图与 XML 布局必须严格配对，杜绝出现“截图更新了但控件树来自上一帧”的不一致现象：
1. **并发拉取**：使用并发 Future 同时触发 `layoutInspectorService.captureScreenshot` 与 `layoutInspectorService.captureLayout`。
2. **原子替换**：当且仅当截图解码与 XML 解析全部成功后，才在同一个 `state = state.copyWith(...)` 事务中更新 `decodedImage`、`rootNode` 与 `xmlContent`。
3. **失效保留**：若布局转储失败（例如 App 处于转场过渡期），保留上一份完整可用的截图和控件树，仅弹出浮层错误，不破坏当前已有数据。
4. **请求失效令牌**：每次刷新或模式切换都会执行 `final currentRequestId = ++_requestId;`。当异步网络 I/O 完成后，对比 `currentRequestId == _requestId && ref.mounted`；若用户已关闭分析模式或触发了更新的刷新，则直接释放中间资源并丢弃响应。

---

## 4. 共享画布与坐标变换 (`ScreenshotCanvas` & `ScreenPreviewPainter`)

- **InteractiveViewer 共享**：不论在普通截图模式还是布局分析模式，均复用同一个 `ScreenshotCanvas`，避免多次创建图层和 GPU 显存浪费。
- **坐标系统一映射**：
  - 手机物理像素坐标：$(X_p, Y_p)$
  - Flutter 逻辑点与 Canvas 局部渲染坐标：$(X_c, Y_c)$
  - 旋转变换：$0^\circ, 90^\circ, 180^\circ, 270^\circ$ 统一在 Painter 矩阵内处理。
- **辅助图层与交互联动**：
  - 显示布局边框（`showBorders`：与画布点击选中联动；勾选“显示布局”时自动支持点击/悬停选中控件节点，未勾选时禁用点击选中）
  - 悬停预览（`hoveredNode`）
  - 单位切换（`useDp`，结合设备 density 进行实时换算并在边框上标注宽高）

---

## 5. 跨平台支持边界

| 平台 | 截图能力 | 录屏能力 | 布局分析开关 | 备注 |
| :--- | :---: | :---: | :---: | :--- |
| **Android** | 支持 (ADB) | 支持 (Screenrecord / Scrcpy) | **展示并支持** | 完整支持 UI Automator 转储与节点选中 |
| **iOS** | 支持 (go-ios) | 保持原有策略 | **隐藏** | 专注投屏与基础诊断 |
| **HarmonyOS** | 支持 (HDC) | 保持原有策略 | **展示并支持** | `uitest dumpLayout` JSON 转换为共享 `LayoutNode`，复用三栏树、画布高亮、属性与 XML 导出 |

---

## 6. 测试与质量保证

针对合并架构建立了全面的测试用例：
1. `test/screenshot_layout_merge_test.dart`：
   - 导航栏仅展示“截图录屏”，原“布局分析”入口已移除。
   - `ToolTabNotifier` 对 Tab 8 的选中请求自动归一化重定向至 Tab 9。
   - 布局分析开关在 Android 下展示，在 iOS / HarmonyOS 下正确隐藏。
   - 开启布局分析后展开左右侧面板并触发并发拉取；关闭后收起面板并保留底图。
   - 录屏各个生命周期阶段（starting / recording / stopping / saving）对开关的禁用与 Tooltip 验证。
   - 原子刷新失败时旧数据的完整性保护。
2. `test/layout_node_test.dart`：XML 树解析、转义字符还原与负坐标 bounds 支持。

## 7. 截图底部工具栏（2026-10-10）

- 将放大、缩小、1:1、重置缩放及 PNG 分辨率/大小信息从 `ScreenshotToolbar` 移至共享 `ScreenshotBottomBar`；顶部保留刷新、保存、复制、旋转、连续截图、录屏和布局分析操作。重置必须复用 `ScreenshotCanvas.resetZoomAndPan()`，按当前视口恢复图片初次加载时的适配大小与居中位置，不能直接写入 `Matrix4.identity()` 导致图片变为 1:1 并移动到左上角。
- `DashboardScreenshotTab` 与 `HarmonyScreenshotTab` 将底栏放在 `Expanded` 工作区之后，固定显示且不覆盖截图；布局分析模式下仍位于整个三栏工作区底部。
- 复用现有画布回调和本地化 Tooltip。无截图或录屏活跃阶段禁用缩放；底栏颜色跟随 Theme，窄窗口允许按钮横向滚动、图片信息省略并提供完整 Tooltip。不新增 Provider 或设备命令，不改变截图、录屏和坐标映射逻辑。
- 验证结果：4 个修改涉及的 Dart 文件定向 analyze 通过，`screenshot_layout_merge_test.dart` 的 7 项既有测试通过；未启动应用，桌面视觉效果尚需实际窗口验收。手动检查普通截图与布局分析模式、明暗主题、窗口缩小、四个缩放操作及录屏时的禁用状态。

## 8. 布局分析局部工具（2026-10-10）

- “展开全部 / 收起全部”从顶部公共工具栏迁移至左侧“节点结构”标题栏，直接操作节点树；布局加载中或尚无节点树时按钮禁用。
- “DP”单位切换从顶部公共工具栏迁移至右侧“属性列表”标题栏，仅在已选择组件并显示属性列表时出现；切换仍复用 `setUseDp`，同步影响属性尺寸和画布标注。
- “显示布局 / 导出 XML / 复制节点 XML”统一以 IconButton 放入左侧“节点结构”标题栏：显示布局使用取景框 icon，开启后以 Theme primary 高亮并继续联动点击选中；导出保存完整布局 XML，复制保持选中节点优先、未选择时复制根节点。
- 顶部工具栏在普通截图和布局分析模式下都只处理图片保存与图片复制；进入布局分析后不再把保存切换为 PNG+XML，也不再把复制切换为 XML。XML 操作不会增加 ADB 请求，继续使用当前原子抓取结果。
- 顶部工具栏继续保留“显示属性”，不改变三栏显隐、节点选中、截图刷新或坐标换算逻辑。
- 验证结果：相关 5 个 Dart 文件及回归测试定向 analyze 通过，`screenshot_layout_merge_test.dart` 与 `layout_properties_table_test.dart` 共 9 项测试通过；未启动应用，实际桌面窗口的视觉间距仍需手动验收。

## 9. 布局分析加载反馈与盒模型（2026-10-16）

- 点击“布局分析”后，Controller 先同步切换模式并写入 `isLoading`，UI 使用 `addPostFrameCallback` 等开关与紧凑的 `CircularProgressIndicator` 完成首帧绘制后，再启动截图/XML 抓取；加载期间仍可主动关闭分析模式，结束或失败后指示器自动消失。
- 属性列表顶部增加盒模型示意：中心展示选中节点的 `width × height`，四周展示相对父节点的 left/top/right/bottom 间距；盒模型只显示数值、不显示单位，但数值仍跟随 PX/DP 开关换算，颜色来自 `ColorScheme`。
- 盒模型作为属性 `ListView` 的第一项，不新增滚动容器或 Provider，不改变节点坐标计算、布局抓取和画布映射逻辑。

## 10. Android 折叠屏截图自动选屏（2026-10-29）

### 问题与实现

- Samsung SM-F9710 展开时，默认 `screencap -p` 实测选中处于 OFF 的外屏，输出全黑 PNG；显式指定 ON 内屏的物理 ID 后画面正常。PNG 数据清理无法解决截错屏幕的问题。
- `lib/core/adb/screenshot_display_selector.dart` 解析 `dumpsys display` 中的 `DisplayDeviceInfo`：只选择 `type INTERNAL / BUILT_IN`、`state ON`、`uniqueId="local:<数字>"` 的屏幕。虚拟屏、外接屏、OFF、DOZE 与 ON_SUSPEND 不参与选择；`committedState` 不能替代当前 `state`。
- 多个内置屏同时 ON 时，优先选择逻辑主屏 `mDisplayId=0` 对应的物理屏，否则选择首个 ON 内置屏。返回字符串形式的 physical displayId，避免与逻辑 ID `0/1` 混用或发生 uint64 截断。
- `AdbService.captureScreenshot` 每次截图先执行 `adb -s <deviceId> shell dumpsys display`，再执行 `adb -s <deviceId> exec-out screencap -p -d <physicalId>`。不缓存屏幕 ID，下一次截图自然跟随折叠或展开后的状态。
- 探测失败、超时、无 ON 内置屏或旧系统输出无法解析时，保留原有不带 `-d` 的截图路径。继续复用 PNG 前后警告文本清理、截图错误与超时进程终止逻辑。
- 探测上限为 `min(3 秒, 调用方总超时 / 4)`，截图只使用总预算的剩余时间；探测进程复用 `AdbService.run` 的超时回收。不启动常驻轮询，不新增依赖、Provider、UI 或跨窗口消息。

### 影响范围与回归

- 自动覆盖使用公共 `captureScreenshot` 的截图工作台、布局分析、控制页截图、批量截图、物理投屏窗口截图与 MCP 截图。显式 Display 截图、录屏与 Rust 投屏流保持原路径；iOS/HarmonyOS 分流保持原逻辑。
- 新增 `test/adb_screenshot_display_test.dart` 的 14 项测试：展开/折叠、同一服务展开→折叠→展开、普通单屏、主屏优先、CRLF、虚拟/外接/休眠屏过滤、uint64、异常回退、USB/TCP 参数、PNG 清理、截图错误、超时终止与共享预算。
- 下列相关回归共 36 项通过：

```bash
flutter test test/adb_screenshot_display_test.dart test/adb_service_test.dart \
  test/screenshot_layout_merge_test.dart test/harmony_layout_inspector_test.dart \
  test/ios_capability_route_test.dart
flutter analyze --no-pub lib/core/adb/adb_service.dart \
  lib/core/adb/screenshot_display_selector.dart test/adb_screenshot_display_test.dart
```

- 修改范围静态检查通过。全量 `flutter analyze --no-pub` 在其他未修改文件中报告 39 项 warning/info，未发现本次修改文件的诊断；未改动无关代码以消除这些存量问题。
- 直接调用修改后的 Dart 服务进行真机验证：SM-F9710 展开状态 USB 与 Wi-Fi 均自动选中内屏 `4630947004648141459`，得到可读的 2448 × 1848 PNG；Mi MIX 3 自动选中单屏，得到可读的 1080 × 2340 PNG。单次总耗时分别约 441 / 1197 / 742 ms（包含状态探测和 PNG 获取，仅代表本次采样）。
- 未启动或重新构建桌面应用。实体合屏后的外屏截图和桌面 UI 切换验收仍待手动验证；折叠路径由自动测试覆盖。读取状态与抓取画面之间若恰好发生折叠切换，当前请求仍可能捕获过渡帧，下一次截图会重新选屏。安全窗口与受保护视频的截图限制仍由 Android 执行。
