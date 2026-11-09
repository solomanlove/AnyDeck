# SVG 与位图资源加载

## 目标与实现

- `AppAssetImage`（`lib/app/widget/app_asset_image.dart`）统一加载本地资源：`.svg` 后缀（忽略大小写）交给 `flutter_svg` 的 `SvgPicture.asset`，其他格式使用 `Image.asset`。
- 使用 `flutter_svg: ^2.3.0`，资源继续由 `pubspec.yaml` 的 `assets/brand/` 目录声明打包。
- 本次解析的传递依赖使 `pubspec.lock` 的 Dart 下限从 3.12 升至 3.13；较旧 SDK 需要重新解析兼容依赖，当前锁文件验证环境为 Dart 3.13 系列。
- 设备列表 `DeviceStatusAvatar` 与侧栏 `_RailIdentity` 的品牌图片共用该组件，品牌 helper 返回 SVG 或 PNG 路径均可加载；品牌匹配规则仍由 `BrandLogoHelper` 负责。
- 支持宽高、BoxFit、对齐、语义描述和自定义 errorBuilder。默认加载失败时保持尺寸并显示主题色破损图片图标。
- 保留素材原色；设备列表离线灰度与透明度继续由外层 ColorFiltered / Opacity 处理，侧栏沿用原有展示样式。
- 使用 StatelessWidget 与库内资源加载机制，不增加 Provider、ADB 进程、MethodChannel 或跨窗口状态；不新增用户可见文案。原生 Dock / 托盘继续使用 PNG。

## 使用方式

```dart
import 'package:any_deck/app/widget/app_asset_image.dart';

const AppAssetImage(
  'assets/brand/xiaomi_logo.svg',
  width: 32,
  height: 32,
);
```

本组件面向已打包的本地资源，不承接设备文件预览或网络图片。新增资源路径仍需纳入 pubspec.yaml 的 assets 声明。

## 服务菜单的平台图标复用

- `ServiceRestartMenuButton` 的 ADB、HDC、iOS 服务项统一调用 `buildPlatformIcon(PlatformDistributionType.android / harmony / ios)`，与现有平台切换器共用 Android、Huawei 花瓣和 Apple Logo，不在菜单中另配平台图标。
- 外层保留 18px 图标列并居中放置 helper 返回的 15px Logo，文字间距和菜单动作保持原实现。
- `test/service_restart_menu_button_test.dart` 在 Light/Dark 下打开真实菜单，检查 Huawei 位图加载、三个 Logo、五项菜单完整性与文字对齐，不执行服务重启；2 项测试通过。未启动桌面 App。

## 平台 Logo 全局复用检查（2026-11-09）

- `buildPlatformIcon(platform, {size = 15})` 统一支持图标尺寸；Android 使用品牌绿色，Huawei 保留位图原色，Apple 使用当前 Theme 的 `onSurface`，避免暗色模式固定黑色不可读。
- 补齐调用：开发者环境诊断的 3 个工具行（20px）和 3 个引导测试按钮（15px）、无线连接弹窗的 Android/HarmonyOS 平台项（18px）、iOS 模拟器空状态（48px）、iOS 版本详情页（24px）。此前已统一的服务菜单和平台版本 Tab 继续复用。
- 模拟器平台 Tab 已经通过 `PlatformVersionSwitcher` 调用公共 helper，无需再次修改；枚举中的图标元数据不参与当前渲染。
- APK 文件类型图标、应用图片加载失败时的占位图、设备厂商品牌图片保留原语义；它们分别表示文件、应用和厂商，不是平台选择/平台标识。天线、网络、调试虫子等功能图标也不替换。
- `test/platform_icon_usage_test.dart` 验证共享 Logo 的 15/20/48px 尺寸、Apple 明暗对比度、诊断区六处 Logo、重新检测和对应平台引导入口；环境结果由测试桩提供，不执行 CLI 探测。
- 本轮 7 个相关测试文件共 31 项通过，6 个实现及测试目标的定向静态分析无问题。未启动桌面 App。

## 验证与回归

- `test/app_asset_image_test.dart` 覆盖真实 SVG / 位图加载，以及两种格式缺失资源时的尺寸与错误回退。
- 自动验证：4 项组件测试通过；用户新增的 `xiaomi_logo.svg` 通过 `vector_graphics_compiler` 编译检查。5 个 Dart 文件定向 analyze 仅报告 `dashboard_screen.dart` 已在 HEAD 存在的 `liquid_glass_background.dart` unused import，无新增诊断；`git diff --check` 通过。
- 手动检查设备列表和侧栏的小米 SVG、Apple/Huawei 位图；切换明暗主题、在线/离线状态与窄侧栏，确认缩放、裁剪、灰度和状态点正常。
- 桌面项目未启动，实际窗口显示效果待手动回归。
