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
3. 无 `BuildContext` 且必须保持品牌色一致时使用 `AppPalette.primary`。
4. 圆角和边框宽度使用 `AppThemeSizes`。

禁止新增以具体色值命名的属性，例如 `gray334155`、`white70`。应按用途命名，例如 `toolbarForeground`、`subtleBorder`。

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
