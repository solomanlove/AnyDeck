# AnyDeck 设置分类导航与全局搜索

## 需求与分类

2026-11-08：将设置长页改为 7 类导航，增加全局搜索与窄窗口适配；保持原有设置值、保存回调和跨窗口同步机制。

| 分类 | 内容与内部 Card |
| --- | --- |
| 常规 | 语言、外观；启动（macOS 开机自启） |
| 投屏与录制 | 画质（预设、码率、分辨率）；窗口与控制（置顶、工具栏、熄屏、前台 App 识别及间隔）；音频（Android / iOS）；录制 |
| 投屏接收 | AirPlay / DLNA 接收名称分别成组 |
| 快捷键 | 原有窗口与软件、投屏窗口动作录入、冲突校验及恢复默认 |
| 通知 | 设备连接通知、正文预览、系统通知权限 |
| 存储与缓存 | 文件保存、缓存管理 |
| 关于与支持 | 版本与更新、已启用的开发者选项入口、意见反馈 |

鸿蒙互联的专属配置保留原入口；未新增设置值、Preference key、协议方法或后台进程。未改变开发者模式激活条件、通知权限申请、AirPlay 名称提交后的空闲重启规则。

## 实现边界

- `dashboard_settings_tab.dart`：原设置入口与 Header，负责装配目录与 Workspace。
- `dashboard_settings_catalog.dart`：常规、快捷键、通知、存储、支持的展示目录。
- `dashboard_settings_media.dart`：投屏、录制与接收展示目录。原设置页的 15 个 Controller 保存回调完整保留，自动启动、通知、缓存等仍走原扩展方法。
- `settings/settings_item.dart`：稳定分类与设置项元数据；名称、说明、关键词、复合控件内部动作名称与 Widget 分离。
- `settings/settings_workspace.dart`：搜索、分类导航、滚动位置与结果定位；不承担设置持久化。
- `dashboard_settings_widgets.dart`：复用原 Card 与设置行；只对窄内容区的行布局增加上下排列。
- 新增可见文案及检索别名位于 `app_l10n_settings.dart`，中英文同步。

## 导航与搜索

1. 默认进入常规，每次只挂载当前分类的控件；切换分类后恢复该分类的滚动位置。
2. 搜索框始终可见，跨 7 类匹配名称、说明、分类、Card 分组及关键词；忽略大小写和首尾空白，多词按 AND 匹配。
3. “声音 / sound”等别名可以匹配音频转发；快捷键还索引当前绑定的按键显示文本。
4. 搜索结果展示所属分类和分组，点击后清空搜索、切换分类、滚动定位并以主题主色标记目标行；快捷键、通知等复合控件优先定位命中的具体动作文案。
5. 搜索不直接修改设置；清除搜索回到原分类。无结果提供提示，手动选择分类会退出搜索。
6. Workspace 可用宽度 ≥900px 显示 160px 分类侧栏；不足 900px 切换分类下拉框。断点按内容区而非整个 App 宽度计算，保留原主侧栏。
7. 设置行扣除 Padding 后宽度不足 480px 时，说明和控件上下排列，避免接收端名称输入框挤压标题；右侧内容最大宽度仍为 860px。

UI 状态由 Workspace 持有，Controller / ScrollController 随销毁释放；延迟定位和滚动恢复通过导航版本号避免旧回调覆盖新操作。不缓存多个完整分类 Widget 树，也不新增日志或投屏订阅。

## 验证与人工边界

```bash
flutter test --no-pub test/settings_workspace_test.dart test/settings_review_test.dart test/keyboard_shortcut_settings_widget_test.dart
flutter test --no-pub test/dashboard_shell_navigation_test.dart
flutter test --no-pub test/app_settings_test.dart test/receiver_name_setting_field_test.dart
flutter analyze --no-pub lib/features/dashboard_screen.dart lib/features/overview/settings lib/app/l10n/tables/app_l10n_settings.dart test/settings_workspace_test.dart test/dashboard_shell_navigation_test.dart
git diff --check
```

共 27 项定向测试通过，定向静态检查与 whitespace check 通过。覆盖中英文、明暗主题、7 类切换、搜索别名/描述/空结果/清除、复合动作定位、滚动恢复、宽窄断点切换，以及真实 Dashboard 中全部分类的宽窄布局与导航不修改设置值。原有快捷键录入/冲突/取消/清除/重置、画质预设持久化和跨窗口广播、接收名称编辑/提交/恢复默认回归通过。

按用户要求未启动桌面 App。真实 DPI、原生窗口缩放、系统权限/目录选择器和真实多 Engine 同步仍需桌面人工验收；这些原生路径保留原实现，自动测试不等同于运行验收。

## 2026-11-08 重构审查与补充修复

对照 `50a668a^` 与重构后的目录逐项检查：原有设置项和 8 个复用入口未遗漏，15 个 Controller 保存回调及 14 个 `value: settings.*` 绑定字段保持一致。录制开关的原硬编码文案只迁入 l10n；自动启动的平台限制、开发者入口条件及通知/缓存逻辑未改变。

审查复现并修复两类问题：

1. 搜索检索按多词匹配，但动作定位原先按连续子串匹配。输入 `Take   screenshot` 时能找到快捷键分类，点击却停留在分类顶部。现在检索和动作定位共用多词匹配规则，并增加 `searchAliases` 将已启用的当前按键组合映射到具体动作文案；按键搜索也定位到实际行。
2. 实际 Dashboard 的英文窄窗口测试发现下拉选择器 Row 横向溢出 12px。原先语言/外观选择器与菜单固定为 112px，现在根据选项文字、字体与 TextScaler 测量宽度，保持选择器与菜单等宽（112–240px），并约束单行文字以避免挤出箭头。

补充验证：

- 先用失败测试复现多空格动作定位，再验证修复；对屏幕外的动作行同时测试多空格和按键别名定位。
- 验证搜索清除与分类切换均能恢复原滚动位置。
- 实际 Dashboard 在中文/英文 × Light/Dark 下，以 900×700 窗口逐一切换全部 7 类，无布局异常；宽窗口导航也保留原回归覆盖。
- 经真实搜索入口点击窗口置顶、强制电脑录制、前台 App 识别开关，确认 Provider 与原 Preference 保存值；识别间隔随识别开关联动，未操作的音频设置保持不变。
- 本轮 28 项相关测试全部通过，定向静态分析和 `git diff --check` 通过。未启动桌面 App；原生窗口与系统服务验收边界仍按上节说明。

## 2026-11-08 设置视觉统一

- 设置分类与主侧栏文字导航统一复用 `AppNavigationItem`，沿用设置 Tab 的 44px 行高、10px 圆角、24px Icon、选中字重、Hover / InkWell 反馈和淡色背景；选中背景、普通/禁用前景集中到 Theme，圆角集中到 `AppThemeSizes.radiusNavigation`，避免分类栏单独使用高饱和矩形背景。主侧栏状态点、Tooltip、点击行为及窄栏模式保留。
- 快捷键行在右侧弹性区域内使用 `Align.centerRight`，窗口与软件、投屏窗口的全部按键按钮统一贴齐 Card 内右边距；长标题保留换行与按键宽度约束。
- 版本号、开发者选项、意见反馈移除前置图标，保留更新按钮、右侧进入箭头、版本号连续点击激活和反馈弹框。
- 18 项相关测试通过：验证主设置 Tab 与设置分类复用组件且选中颜色/圆角一致，全部快捷键按钮右边缘对齐，中英文/明暗/宽窄导航、搜索和保存回归，以及无前置图标后的开发者模式激活与行边缘对齐。定向静态分析与 diff check 通过；未启动桌面 App，实际窗口视觉仍待人工验收。

## 2026-11-08 下拉菜单边缘对齐

投屏码率、最大分辨率、前台 App 识别间隔接入既有 `alignMenu` 模式，与语言/外观一致：触发按钮和菜单共用测量宽度，菜单在按钮下方展开，不再通过固定 offset 或选中项中心定位产生横向错位。保存回调和选项值保持原样。

`dashboard_shell_navigation_test.dart` 5 项测试通过，新增实际 Dashboard 在 900px / 1600px 窗口下的码率、分辨率菜单左右边缘及下方展开断言，并验证选择后原 Preference 正常写入。定向静态分析和 `git diff --check` 通过；未启动桌面 App。

## 2026-11-08 快捷键分组标题外置

快捷键分类移除内容区重复的“快捷键”总标题，拆为“窗口与软件”“投屏窗口”两个独立 Card，使用其他设置相同的外部分组标题。侧栏的快捷键分类名称保留。

`KeyboardShortcutSettings.group` 仅选择渲染哪组内容；单组模式不再渲染内部标题，录入、冲突校验、禁用、恢复默认及保存流程均复用原逻辑。未指定 group 时保留组件原有完整列表行为。设置目录分别维护两组动作与按键别名，搜索仍可定位具体动作；按钮继续靠右。

16 项相关测试通过，覆盖实际 Dashboard 的两组标题各显示一次且位于内容组件外、不再显示总标题，以及中英文/明暗主题、宽窄布局、搜索、录入/冲突/取消/清除/恢复默认回归。定向静态分析与 diff check 通过；未启动桌面 App。
