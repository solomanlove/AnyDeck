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

## 验证与回归

- `test/app_asset_image_test.dart` 覆盖真实 SVG / 位图加载，以及两种格式缺失资源时的尺寸与错误回退。
- 自动验证：4 项组件测试通过；用户新增的 `xiaomi_logo.svg` 通过 `vector_graphics_compiler` 编译检查。5 个 Dart 文件定向 analyze 仅报告 `dashboard_screen.dart` 已在 HEAD 存在的 `liquid_glass_background.dart` unused import，无新增诊断；`git diff --check` 通过。
- 手动检查设备列表和侧栏的小米 SVG、Apple/Huawei 位图；切换明暗主题、在线/离线状态与窄侧栏，确认缩放、裁剪、灰度和状态点正常。
- 桌面项目未启动，实际窗口显示效果待手动回归。
