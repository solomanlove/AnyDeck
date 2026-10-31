# 应用图标缺失时的平台回退

## 适用范围

`AppsTab` 与 `HarmonyAppsTab` 共享应用列表、网格、详情和权限弹窗。图标展示统一由 `lib/features/apps/widgets/package_icon.dart` 的 `_PackageIcon` 负责；使用时长弹窗也复用该组件。Android `ProcessesTab` 在真实图标不可用时也使用同一 Android 默认图标资源，避免进程列表与应用列表展示不同的占位图标。

## 展示顺序

1. `AdbPackage.iconLocalPath` 指向存在且能解码的文件时，展示提取或缓存的应用图标。
2. 路径为空、文件不存在或图片解码失败时，读取 `deviceRegistryProvider` 中目标 `deviceId` 的 `DiscoveredDevice.isHarmony`。
3. Android 使用用户提供的默认图标 `assets/brand/android_default_app_icon.png`；HarmonyOS 使用 `assets/brand/harmony_default_app_icon.png`。后者取自 [HarmonyOS Empty Ability 项目模板的 `app_icon.png`](https://github.com/linhay/harmony-next.skills/blob/master/harmony-next/references/templates/empty-ability-app/AppScope/resources/base/media/app_icon.png)，模板说明其为默认应用图标。不同系统版本的实际缺省图可能不同，如需精确匹配指定设备，应替换此资源。

进程列表会先按基础包名关联应用元数据并尝试展示真实图标；缓存路径不存在或图片解码失败时，Android 回退到 `AppIcons.androidDefaultAppIcon`，HarmonyOS 回退到 `AppIcons.harmonyDefaultAppIcon`。系统进程、Flutter 应用和普通用户应用不再分别绘制齿轮、网格或手机图标。

图标资源由 `pubspec.yaml` 已有的 `assets/brand/` 目录声明自动打包。不修改 `AdbPackage` 缓存内容，也不在本地或设备端写入兜底图片，因此刷新图标后可直接显示真实图标。

## 验证边界

- 分别检查 Android 与 HarmonyOS 的列表、网格、详情和权限弹窗：有图标、无路径、失效路径及损坏图片四种状态。
- 静态分析只能确认 Dart 调用关系和资源路径；实际图标外观需在桌面 App 中用目标设备查看。
