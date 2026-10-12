---
description: Flutter UI Theme、颜色、边框与尺寸统一规范
globs:
  - "lib/**/*.dart"
alwaysApply: true
---

# UI Theme 统一规范

## 1. 强制使用项目 Theme

- 新增或修改 Page、Dialog、Widget、Overlay、Toolbar、Table、Card 等 UI 时，必须优先使用 `Theme.of(context)`、`ColorScheme`、`AppThemeColors` 和 `AppThemeSizes`。
- 禁止在业务 UI 中新增 `isDark ? ColorA : ColorB` 形式的明暗配色。Light/Dark 差异必须收口到 `lib/app/theme/`。
- 禁止在多个业务文件重复写相同的 `Color(0x...)`、`BorderSide`、`BorderRadius` 或透明度组合。

## 2. 调用优先级

1. Material 标准语义使用 `Theme.of(context).colorScheme`，例如 `primary`、`error`、`surface`、`onSurface`、`outline`、`outlineVariant`。
2. ColorScheme 未覆盖的项目语义使用 `Theme.of(context).appColors`，例如工具栏前景、玻璃表面、弱分隔线和 Hover 表面。
3. 品牌固定色或没有 `BuildContext` 的 Painter/Controller 使用 `AppPalette`；能够由 Widget 注入主题色时，优先通过构造参数注入。
4. 圆角、边框宽度等 UI 尺寸使用 `AppThemeSizes`。

## 3. 允许保留的业务颜色

- Terminal ANSI、命令类型与语法颜色；
- Logcat Level、错误、警告和成功状态色；
- Performance 图表数据序列色；
- Android、iOS、HarmonyOS 及设备厂商品牌色；
- 截图标注、布局节点高亮、二维码和设备真实画面要求的固定颜色。

保留固定色时，命名必须体现业务含义，禁止使用 `gray334155`、`white70` 等纯色值命名。

## 4. 新增 UI 自检

- [ ] Light、Dark、System 三种模式均可读。
- [ ] 未新增重复的明暗三元配色或品牌色十六进制值。
- [ ] Card、Dialog、Input、Button 优先复用 `ThemeData` 的组件主题。
- [ ] Painter、Controller、Service 未反向依赖 Widget Theme。
- [ ] 公共 Widget 的颜色参数具有语义，且默认值来自项目 Theme。
