# UI Theme 统一机制

## 1. 目标与适用范围

本机制统一 AnyDeck 的品牌色、明暗主题语义色、边框及圆角规格，避免业务页面重复编写 `isDark ? ... : ...`、品牌色十六进制值和边框尺寸。

适用于主窗口、投屏子窗口、模拟器窗口及其他基于 `buildAppTheme()` 创建的 Material App。各窗口运行在独立 Isolate，但都会装配相同 Theme，无需新增 MethodChannel；主题模式仍由现有 `appSettingsProvider` 同步。

## 2. 分层职责

| 文件 | 职责 |
| --- | --- |
| `lib/app/theme/app_palette.dart` | 保存与 Light/Dark 无关的品牌基础色，非 UI 或无 `BuildContext` 的 Painter/Controller 可使用 |
| `lib/app/theme/app_theme_colors.dart` | 通过 `ThemeExtension` 提供工具栏前景、玻璃表面、业务状态等语义颜色 |
| `lib/app/theme/app_theme_sizes.dart` | 保存边框宽度、圆角等不随主题变化的 UI 尺寸规范 |
| `lib/app/theme/app_theme.dart` | 组装 `ColorScheme`、ThemeExtension 和 Material 组件主题 |

## 3. 调用优先级

1. Material 标准语义优先使用 `Theme.of(context).colorScheme`：
   - 品牌主色：`colorScheme.primary`
   - 错误色：`colorScheme.error`
   - 普通边框：`colorScheme.outlineVariant`
   - 强边框：`colorScheme.outline`
2. ColorScheme 没有表达的业务语义使用 `Theme.of(context).appColors`：
   - 投屏及控制工具栏前景：`appColors.toolbarForeground`
   - 桌面玻璃表面：`appColors.glassSurface`
   - 面板与下沉背景：`appColors.panelSurface`、`appColors.sunkenSurface`
   - Hover 与弱背景：`appColors.hoverSurface`、`appColors.subtleSurface`
   - 分隔线与弱化文本：`appColors.subtleDivider`、`appColors.softDivider`、`appColors.mutedForeground`、`appColors.faintForeground`
3. 无 `BuildContext` 且必须保持品牌色一致时使用 `AppPalette.primary`。
4. 圆角和边框宽度使用 `AppThemeSizes`。

禁止新增以具体色值命名的属性，例如 `gray334155`、`white70`。应按用途命名，例如 `toolbarForeground`、`subtleBorder`。

所有新增 Page、Dialog、Widget、Overlay、Toolbar、Table 和 Card 必须遵守 `agent/rules/60-ui-theme.md`，不得在业务 UI 中新增明暗颜色三元表达式。

## 4. 固定业务颜色边界

以下颜色不强制迁移为全局主题色：

- Logcat Level、性能图表数据序列等具有数据含义的颜色；
- Android、iOS、HarmonyOS 或设备厂商的品牌颜色；
- 截图标注、布局节点高亮等需要固定辨识度的颜色；
- 设备屏幕、二维码等协议或内容要求固定黑白的颜色。

Painter 或 Controller 不应反向依赖 Widget Theme；需要动态主题时，由 Widget 解析颜色后通过构造参数注入。

## 5. 验证与回归边界

- 自动验证：运行 `flutter analyze`，确保不存在本次引入的 compile error。
- 手动回归：分别切换 Light/Dark/System，检查主窗口、投屏窗口、AirPlay、Android/iOS/HarmonyOS 模拟器管理页的图标、文字和边框对比度。
- 本次主题治理只修改 UI 样式来源，不修改投屏触控、ADB/HDC 命令、后台进程、Provider 或跨窗口通信协议。
- 按项目规则不自动运行 App；真实桌面材质和多窗口视觉效果仍需后续人工验收。

## 6. 装饰卡片与 Material 交互层

- 当 `Container` / `DecoratedBox` 提供背景色、边框、圆角或阴影，且内部包含 `ListTile`、`InkWell` 等 Material 交互组件时，装饰层与交互组件之间必须放置 `Material(type: MaterialType.transparency)`。
- 该透明 Material 负责承载 Hover、Ink splash、`tileColor` 等绘制，外层装饰继续负责卡片背景和裁剪，避免 Flutter 抛出 `ListTile background color or ink splashes may be invisible` 断言。

## 7. 全局轻提示

- 普通成功、失败、警告和信息反馈统一由 `lib/app/widget/app_toast.dart` 的 `AppToast.show(...)` 渲染，位置固定为当前窗口 SafeArea 内顶部居中，距顶部 16px。
- `AppToast` 是唯一 Overlay 视觉实现；旧 `DashboardSnack.show(...)` 仅保留兼容调用并转发到 `AppToast`，禁止再维护独立布局。
- 同一 Isolate 同时只展示一条轻提示，新提示替换旧提示并重置隐藏 Timer；页面切换或测试清理可调用 `AppToast.dismiss()`。
- Dialog、确认框、进度面板以及包含用户操作的 Material SnackBar 不属于无交互轻提示，不应仅为统一位置而移除其交互能力。
- 2026-10-27 定向验证：`app_toast_test.dart` 覆盖 `AppToast` 与兼容入口均在顶部居中、后发提示替换前一条及主动关闭；Widget test 与 targeted analyze 通过。按项目规则未运行 App，真实多窗口视觉仍需人工验收。

### 轻提示偶发残留修复（2026-10-29）

- 问题：投屏窗口的“已复制到剪贴板”等提示偶尔超过默认 1600ms 仍不消失。`OverlayEntry.mounted` 仅表示其 Widget 已挂载，不表示 entry 是否仍归 Overlay 所有；刚插入尚未绘制、被 opaque entry 遮挡时都可能为 false。
- 根因：旧 `dismiss()` 仅在 `mounted == true` 时执行 `remove()`，随后却清空引用并取消 Timer。若同一帧连续显示两条提示，旧 entry 会失去 Timer 并永久残留；被不透明弹层遮挡期间到期也会漏删，弹层关闭后重新出现。新增测试在修复前稳定复现上述两种情况及首帧前主动关闭漏删，共 3 项失败。
- 修复：成功 `overlay.insert(entry)` 后才记录当前 entry；关闭时先取消 Timer、取出并清空引用，再无条件对所属 entry 执行 `remove()` 与 `dispose()`。不以 Widget 的 mounted 状态判断所有权，重复关闭安全，释放 entry 通知器资源。默认时长、提示样式、交互穿透与新提示重新计时保持原逻辑。
- 影响范围：公共 `AppToast` 与兼容入口 `DashboardSnack`，包括主窗口和独立投屏窗口。无新增依赖、Provider、MethodChannel、设备命令或轮询，不改变投屏 Texture、输入和剪贴板协议。
- 自动回归：`app_toast_test.dart` 共 7 项，覆盖顶部居中、默认到期关闭、同帧替换、首帧前关闭、不透明弹层遮挡后到期、重置计时、Overlay 销毁与新窗口重建；连同 `mirror_clipboard_sync_test.dart` 共 11 项通过。修改范围静态检查与 `git diff --check` 通过。
- 扩展验证：`ios_mirror_toolbar_test.dart` 的 4 项按钮数量断言预期 6 个、实际 8 个；临时使用 HEAD 原版 `AppToast` 重跑同样 4 项仍失败，确认是既有测试问题，已恢复本次修复文件并保持 iOS 工具栏代码不变。该文件的控制失败弹框用例通过。
- 全量 `flutter analyze --no-pub` 仍在其他未修改文件报告 39 项既有 warning/info，本次修改文件无诊断。
- 未启动 App。真实投屏窗口中连续截图、隐藏/恢复窗口及弹层覆盖后的视觉效果仍待人工验收；Flutter 无新绘制帧时，屏幕上的旧像素需等窗口恢复绘制才会更新，entry 的逻辑移除不依赖 Ticker 或动画。

```bash
flutter test test/app_toast_test.dart test/mirror_clipboard_sync_test.dart
flutter analyze --no-pub lib/app/widget/app_toast.dart test/app_toast_test.dart
```
