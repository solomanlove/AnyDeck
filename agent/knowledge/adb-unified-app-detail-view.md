# 应用详情统一展示模型与 UI

## 目标

本地 APK 详情与设备已安装应用详情共用同一套 presentation data structure 和顶层 Widget，避免两个页面分别维护标题、版本、标签、字段、复制按钮、响应式分栏和 Tab 样式。

```text
LocalApkInfo ------------------- buildLocalApkDetailViewData --┐
                                                              ├─ AppDetailViewData ─ AppDetailView
AdbPackage + AdbPackageDetail -- Installed Adapter -----------┘
```

## 统一数据结构

`lib/app/widget/app_detail_layout.dart` 定义：

- `AppDetailViewData`：名称、版本、Logo、Badge、概要字段和 Tab 元数据。
- `AppDetailLogoData`：真实 Logo 与平台默认回退图片；统一组件负责尺寸、圆角和加载失败回退。
- `AppDetailSummaryBadge`：ABI、Framework、DEBUG 等标签及其语义色。
- `AppDetailSummaryField`：字段名称、值、复制能力、颜色和最大行数。
- `AppDetailTabData`：稳定 ID、标题和可选数量。

业务层只负责将原始模型转换为上述展示模型，不在公共 Widget 中判断 `LocalApkInfo`、`AdbPackage` 或 `AdbPackageDetail` 类型。

## 统一 UI

`AppDetailView` 是红框内容区域的唯一顶层 Widget，统一负责：

1. `AppDetailSplitView` 的左右分栏与窄窗口上下布局。
2. `AppDetailSummaryPanel` 的 Logo、名称、版本、标签、字段和复制按钮。
3. `TabBar`、数量文案、间距与 `TabBarView` 容器。
4. Dark/Light 主题下的背景、边框和语义色。

本地 APK 使用标准 `tabViews`；已安装应用在详情加载、失败时通过 `tabBody` 注入状态内容，成功后仍返回对应 `TabBarView`。Tab 标题和概要始终来自同一个 `AppDetailViewData`。

## 业务边界

统一的是 presentation model 与 UI，不合并底层 source of truth：

- 本地 APK 仍由 Rust 离线解析，权限表示 Manifest 声明，签名表示 APK 内 v1/v2/v3/v3.1 证书。
- 已安装应用仍由 ADB/PackageManager 获取，权限带当前用户授权状态，签名表示系统认可的 current/past signer。
- 安装、启动、强停、冻结、授权等操作继续由原控制器和 Service 执行，不进入公共展示 Widget。

## 验证边界

- `test/apk_details_page_test.dart` 同时验证 Light/Dark、最小窗口无溢出，并断言页面只使用一个 `AppDetailView` 和一个 `AppDetailSummaryPanel`。
- 定向 `dart analyze` 无本次新增错误；既有 `dashboard_screen.dart` unused import 与加固检测 `print` 提示不属于本次改动。
- 按仓库规则未启动 Flutter 项目；本地 APK 独立窗口与已安装应用详情的最终视觉一致性仍需手工验收。

手工回归重点：

1. 同一 APK 在本地详情与安装后详情中，名称、版本、ABI、SDK 和 Tab 样式应一致。
2. 亮色/暗色下检查概要背景、分隔线、Badge、复制按钮及长文件路径可读性。
3. 检查本地 APK Logo 与设备缓存 Logo；缺失、路径失效或解码失败时应显示对应平台默认图标。
4. 将窗口缩窄到 720 px 以下，确认左右分栏切换为上下布局且 Tab 内容仍可滚动。
5. 本地 APK 权限与签名保持只读；已安装应用的授权、撤销、启动、强停等操作仍可使用。
6. 本地 APK 底部设备选择和安装栏不应被统一详情区域遮挡。
