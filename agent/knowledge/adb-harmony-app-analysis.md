# HarmonyOS 已安装应用独立分析页

## 目标

HarmonyOS NEXT 设备的应用详情不能复用 Android `adb dumpsys package`、`app_process` Helper 或 APK/DEX 模型。Apps Tab 在打开详情前先通过 HDC 验证当前 bundle 是否支持 `bm dump`，成功后进入独立的 HarmonyOS 分析页；命令失败或 JSON 不可解析时停留在应用列表，只展示错误提示。

## 数据链路

```text
HarmonyAppsTab
  -> AppsTab._openPackage(bundleName)
  -> AppManagementService.getHarmonyPackageDetailedInfo()
  -> HdcService.shell("bm dump -n <bundleName>")
  -> HarmonyAppDetailParser
  -> HarmonyAppDetail
  -> _HarmonyAppAnalysisView
```

- `lib/core/apps/harmony_app_detail.dart`：HarmonyOS 专属 Model 与纯 Dart parser。
- `lib/core/apps/app_management_service_harmony_detail.dart`：HDC/BM 查询入口；校验 `bundleName` 后再执行命令，禁止回退 ADB。
- `lib/features/apps/harmony_app_analysis_view.dart`：独立页面，复用公共 `AppDetailView` 布局，但不复用 Android `_AppFunctionsView`、Tab 或操作逻辑。
- `lib/features/apps/dashboard_apps_tab.dart`：打开 HarmonyOS 详情前执行能力探测，成功才写入 `selectedAppPackageProvider`。

## 可分析字段

`bm dump -n` JSON 当前提取以下信息：

1. Bundle：`bundleName`、版本、兼容/目标 API、Compile SDK、CPU ABI、发布类型、安装来源、开发者/组织、签名指纹、安装/更新时间和 code path。
2. HAP Module：模块名、主入口、HAP 路径、设备类型、Native Library。
3. 组件：`UIAbility`、`ExtensionAbility`、入口源码、进程、可见状态、Action、Entity 和组件权限。
4. 权限：声明权限、所属 Module、申请原因与使用场景。
5. Metadata：按 Module 合并展示的键值信息。

## 不支持与安全边界

- Bundle 不满足 HarmonyOS `bundleName` 字符规则时，不执行 HDC 命令，避免 shell 参数注入。
- 设备离线、HDC 不可用、`bm dump` 失败或输出不是有效 JSON 时，抛出 `HarmonyAppAnalysisUnsupportedException`，调用方不跳转页面。
- HarmonyOS 单击应用只更新本地选中态，不使用单包刷新来推断是否卸载，避免不支持 `bm dump` 的应用被误删出列表。
- 页面仅展示设备公开给调试通道的静态/安装态信息，不代表可以读取应用源码、私有数据或绕过系统权限。

## 验证边界

- 真机只读验证：`nova 12 Ultra`、HDC serial `2UCUT23C18017189`，`bm dump -n com.droi.tong` 返回完整 Bundle/HAP/Ability/权限 JSON。
- `test/harmony_app_detail_test.dart` 覆盖 parser、非法输出、HDC-only 路由和恶意 bundleName 拦截。
- 按仓库规则未启动 Flutter 项目；页面最终视觉、双击交互、Light/Dark 与不同 HarmonyOS 版本的字段兼容性仍需手工验收。
