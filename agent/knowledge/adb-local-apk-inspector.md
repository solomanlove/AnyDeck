# macOS Android 安装包分析与 APK 安装

## 用户路径与能力边界

在 Finder 中对 `.apk`、`.apks`、`.aab` 或 `.xapk` 选择「打开方式 → AnyDeck」，应用会为每个文件打开独立详情窗口。同一路径或指向同一文件的符号链接复用已有窗口；不同目录的同名文件分别打开。设置各类安装包默认由 AnyDeck 打开，需要对各扩展名分别在 Finder「显示简介 → 打开方式 → AnyDeck → 全部更改」中完成；注册文件类型不会覆盖现有默认选择。

详情窗口离线展示名称、图标、包名、版本、SDK、ABI、DEBUG、文件大小，以及原生库、组件、声明权限、Metadata、DEX、签名证书。`targetSdk` 明确表示目标 SDK，不能作为最高支持版本。未声明的 `maxSdk`、`exported` 或其他字段不推测填充；本地详情没有安装时间、授权状态、设备启用状态。

- 解析器随 `.app` 分发，无需运行时 Android SDK、Java、Rust 或手机连接。
- 安装仍复用宿主机 `adb`，只支持可独立安装的单个 APK。APKS、AAB、XAPK 当前支持离线分析，不提供安装操作；标记为 split 的单个 APK 同样禁止单独安装。
- 签名页为证书读取，**没有执行 APK 完整性验签**；覆盖安装最终由设备 PackageManager 校验。
- 优先读取 PNG/WebP/JPEG 图标，adaptive XML 会尝试同名位图变体，无法渲染时显示统一 Android 占位图。
- 原有主窗口及投屏窗口的拖拽安装流程不变。

## APKS / AAB / XAPK 分析（2026-11-07）

| 格式 | 分析能力 | 安装边界 |
| --- | --- | --- |
| APK | 原有组件、权限、原生库、DEX、签名及安装 | 沿用单 APK 安装 |
| APKS | 根据内含 Manifest 选择 base，展示 APK 清单、来源、同包/同版本的组件与文件汇总 | 仅分析，不猜测设备所需 split 组合 |
| XAPK | APKS 同类能力，额外展示 OBB 清单与 manifest.json 元数据 | 仅分析，不自动推送 OBB |
| AAB | 读取 base、feature、asset pack 模块和 Protobuf Manifest/resources.pb，解析名称、版本、SDK、组件、权限、模块 ABI/DEX/SO 与 JAR 上传证书 | 仅分析，不生成 APK 或要求用户安装 Java/SDK |

### 入口、模型与 UI

- macOS 的 URL、openFiles 回调及 Info.plist 同时接收四类扩展名。APKS 注册 `com.android.package-set`，AAB 注册 `com.android.app-bundle`，XAPK 注册 `com.android.package-xapk`。
- Dart 使用 `AndroidPackageFormat` 统一扩展名判断；窗口仍用原路径身份，JSON 在旧字段之外增加 `format`、`splitName`，容器提供 `primaryEntry/archiveEntries/containerMetadata`，AAB 提供 `modules`。
- `LocalApkInfo.analysisOnly` 与 `installable` 区分展示与安装。容器页面使用统一 `AppDetailView`，新增分包/模块、容器元数据 Tabs；不创建设备查询或安装栏，Controller 也拒绝安装只读格式。
- 文件格式显示在概况中，标题、警告和说明支持中文/英文及 Light/Dark。原有 APK 详情 Tabs 与安装流程保留。

### 容器与 AAB 解码

- APKS/XAPK 逐个解析内含 APK，最终以真实 Manifest 的 `split` 声明判定 base；不依赖文件名或 XAPK manifest.json 冒充包名、版本。名称只用于同等 base 候选的稳定排序。
- 只有同包名、同版本的 APK 参与汇总；组件语义去重，DEX/SO/证书保留 `source`。不匹配或损坏的分包仍保留清单和警告。不同设备变体的汇总不代表实际可同时安装。
- OBB 只记录文件名与未压缩大小，不解包。XAPK manifest.json 仅作为额外元数据，不能覆盖 APK 信息。
- AAB 解析遵循 [Android App Bundle 格式](https://developer.android.com/guide/app-bundle/app-bundle-format) 和 [AAPT2 Resources.proto](https://github.com/aosp-mirror/platform_frameworks_base/blob/master/tools/aapt2/Resources.proto)。有界 Protobuf reader 跳过未知字段，处理 XML 节点、编译属性、基础类型、字符串、文件和资源引用；资源优先默认配置，循环引用最多追踪 16 次，XML 深度最大 64。
- AAB 的 base 概况为信息源，其他模块按包名合并组件；资源包允许没有 application，并显示交付类型。资源无法解析或个别非 base 模块损坏时保留其他可用内容。
- AAB 签名展示标为 `JAR v1` 上传证书；不当作 APK v2/v3 证书，也不声称完成完整性验签。上传证书可能与商店分发 APK 的签名不同。

### 临时文件、限额与依赖

- 无新增 Dart/Rust 第三方依赖，继续使用锁定的 apk-info/zip 等库。
- 复用现有输入 1 GiB、ZIP 条目 100000、输出 16 MiB、Manifest 16 MiB 限额。每个容器最多分析 256 个 APK，内含 APK 未压缩大小总和最多 1 GiB；AAB 资源表累计最多 128 MiB。
- 分包采用串行检查，始终写入私有临时目录的固定文件名，不使用容器内路径写文件，防止目录逃逸。Dart 通过 `ANYDECK_APK_WORK_DIR` 指定父目录；完成、失败、超时或窗口释放终止进程后递归清理，Rust 正常退出时也会回收自己的目录。
- AAB 的 DEX/SO 和模块体积只读 ZIP 清单，不整体解压。解析过程沿用 30 秒超时，超限或损坏时返回明确错误。

### 测试与人工边界

- 本次验证（2026-11-07）：17 项 Rust 测试与 33 项 Dart/Widget 测试通过，定向 analyze 无问题，macOS Debug 构建与包签名检查通过。打包 helper 已直接检查 APKS、XAPK 和 AAPT2 转换的真实 Protobuf AAB 样本。
- 全仓 analyze 没有编译错误，仍有其他模块既有的 56 条 warning/info；本次未修改这些无关代码。

- Rust 使用 AAPT2 36.0.0 生成的真实 AXML/Protobuf 小型样本，测试运行时不需要 SDK。样本来源和再生成步骤见 `rust/apk_inspector/tests/fixtures/README.md`。
- 自动覆盖 APKS base 选择、feature 汇总、XAPK OBB/元数据、包名冲突、损坏分包、危险路径、空容器、分包数量限额、AAB 模块/资产交付/资源引用/上传证书，以及原有 APK v1/v2/v3 读取。
- Dart/Widget 覆盖三种新格式入口、冷启动队列、中文/大写扩展名、只读模式不查询设备或安装、中英文明暗主题、模块/分包清单、最小窗口及临时目录回收。
- 人工验收：从 Finder 分别选择 APKS/AAB/XAPK 的 AnyDeck 打开方式，检查冷启动、同文件重复打开和多窗口；使用真实业务大包复核模块/分包与名称、SDK、ABI，确保不同变体不被误认为一套安装组合。本次不启动 AnyDeck，不执行真机安装。

## 架构与数据流

| 模块 | 责任 |
| --- | --- |
| `macos/Runner/AppDelegate.swift` | 接收 `application(_:open:)` URL 与 `application(_:openFiles:)`；Flutter 握手前暂存路径 |
| `macos/Runner/Info.plist` | 注册 `com.android.package-archive`、APK 扩展名和 MIME |
| `lib/app/window/apk/` | 主窗口文件协调、设备 RPC、安装回调和子引擎入口 |
| `lib/core/apk/` | 文件队列、静态模型、解析进程、设备客户端及安装状态 |
| `lib/features/apk/` | 左侧概况、只读 Tabs、设备选择与安装栏 |
| `rust/apk_inspector/` | 独立只读检查器及锁定的依赖、第三方许可 |
| `script/build_apk_inspector.sh` | 随 Xcode 构建 helper、嵌入 `.app`、签名 |

### 文件与窗口

1. FlutterAppDelegate 已实现 URL 打开回调，AppKit 可能优先调用该方法，因此同时接入 URL 与文件路径两种入口；非 APK URL 仍转交原有 Flutter 处理。`any_deck/apk_files` MethodChannel 的 `ready` 返回启动期间的路径；后续通过 `openFiles` 推送。
2. `ApkFileOpenQueue` 等待主引擎首帧完成，串行规范化文件路径后创建窗口，避免冷启动或连续打开竞争。
3. `apk_details` 参数包含 `path`、`mainWindowId`，窗口身份为类型与规范化路径。复用 `createAdbManageWindow`，其他类型原有设备/投屏参数去重规则不变。
4. 子引擎复用现有 `AppSettingsController` 的主题、语言广播与 `WindowCloseShortcut`；原生标题同步本地化。最小尺寸 900×600，默认 1120×780，标题拖拽区避让 macOS 按钮。

### 解析协议与资源管理

`Contents/Helpers/anydeck-apk-inspector <absolute-apk-path>` 向 stdout 输出一份 JSON，失败输出 `error` 并以非零状态退出。Dart 通过参数数组调用，不拼接 shell。

JSON 包含 `packageName`、`label`、版本和 SDK、`split`、`debuggable`、`abis`、可选 base64 `icon`，以及 `activities/services/receivers/providers/permissions/metadata/dex/libs/signatures/warnings` 列表。Dart 补充文件 `size`、`modified`，模型 `LocalApkInfo` 与设备 `AdbPackage` 缓存隔离。

- `apk-info = 1.0.12`，全部传递依赖由 Cargo.lock 固定。Rust helper 是单独 Cargo 项目，不链接设备桥接库。
- SO/DEX 只读 ZIP 清单及大小，不反编译或整体解压。ARSC 失败时尝试只读 AXML，保留组件等可用信息。
- 每次刷新重新读取文件；解析前后比较大小与修改时间，安装前再次检查，发现替换要求先刷新。
- 输入最大 1 GiB、ZIP 最多 100000 条目、ARSC 最大 128 MiB、Manifest/证书条目最大 16 MiB、图标最大 4 MiB；解析结果最大 16 MiB，stderr 最大 64 KiB。
- 解析 30 秒超时，完成、超时、输出过量或 Provider 释放时终止进程。`apk-info` 会读取 APK 字节，超大 APK 仍有明显内存成本；窗口独立，关闭窗口释放对应进程和快照。
- 名称资源、drawable 或证书无法完整读取时保留可用信息，提示解析警告。证书页支持 v1/v2/v3/v3.1 主体和 MD5/SHA-1/SHA-256，不把渠道块、Source Stamp 当应用签名。

### 安装与主窗口导航

通过现有 `SubWindowMethodDispatcher` 在主引擎注册处理器，子窗口用实际 `mainWindowId` 的 WindowController 调用：

| RPC | 请求与结果 |
| --- | --- |
| `apk_devices` | 返回设备列表、实际 serial、在线状态、主窗口首选设备；多个窗口共享 2 秒快照 |
| `apk_install` | `requestId/serial/path/packageName/size/modified`；返回 `success/error/warning/serial/packageName` |
| `apk_show_installed` | `serial/packageName`；刷新并选中设备、Apps Tab（2）及应用详情 |

- 设备 UI 每 3 秒读取快照，按 registry 物理身份合并连接并保留实际通信 serial；安装前重新读取实际 ADB 状态，过滤 iOS/Harmony。
- 单在线设备自动选择；多设备优先有效的显式选择或主窗口首选。显式选择的 serial 断开时不自动改装另一台设备。
- `ApkInstallQueue` 合并执行中的相同 requestId，同 serial 串行，不同设备独立。点击安装后按钮禁用、目标锁定。
- 命令复用 `AppManagementService.installApk()`：`adb -s <serial> install -r <path>`。不自动卸载、清数据或添加降级参数。
- 主窗口持有任务，关闭 APK 子窗口不会取消安装。成功后等待 `PackagesNotifier` 初次缓存加载完成，再执行 `refreshSinglePackage` 和持久化缓存，避免初始 loading 状态下刷新被跳过。
- 缓存刷新失败单独返回 warning，不把成功安装改报失败；「查看设备中的应用」会重试刷新。成功 serial 单独保留，不跟随下拉框后续变化。

## 构建与分发

```bash
flutter build macos --release
cargo test --locked --manifest-path rust/apk_inspector/Cargo.toml
```

Xcode 的 `Embed APK Inspector` phase 调用构建脚本，根据 `ARCHS` 编译对应 Rust target；多架构使用 lipo 合并。helper 放入 `Contents/Helpers`，使用当前签名身份签名；许可文件复制至 `Contents/Resources/apk-inspector-licenses`。构建机需要 Cargo 及对应 target，发布后的用户不需要这些工具。

第三方版本和许可证清单见 `rust/apk_inspector/licenses/NOTICE.md`。更新 Cargo.lock 时应同步许可证目录。

## 自动验证与手动回归

自动验证不启动 AnyDeck 主程序，也不连接或安装到真实设备。

- Rust：真实 `usage_companion.apk` 的包名、权限、DEX 与 v1/v2/v3 证书；Manifest SDK/组件语义；损坏资源回退；模拟多 ABI、多 DEX；无效文件拒绝。
- Dart：安装队列串行/去重/错误恢复；首个设备缓存加载后刷新；准确 serial、离线不切设备、文件替换、签名冲突；解析中文路径、重新读取、损坏输出、输出限制与超时；冷启动文件排队与符号链接路径归一化；APK 窗口去重及旧窗口规则回归。
- Widget：离线信息可用、无设备禁用安装、SDK 标签、明暗主题与最小窗口无布局溢出。

```bash
flutter test test/local_apk_test.dart test/apk_install_coordinator_test.dart \
  test/apk_window_open_test.dart test/apk_details_page_test.dart
```

### 必须人工验收的系统/设备链路

1. 将新版本 AnyDeck 放入 Applications，通过 Finder「打开方式」选中它；冷启动、运行中、主窗口隐藏时均打开详情，系统默认关联需要单独设置。
2. 同时打开两份 APK；再次打开同一文件和符号链接应只聚焦既有窗口；窗口拖拽、Cmd+W、语言与主题切换正常。
3. 在无 adb、无设备、未授权、离线状态下仍能查看静态信息；USB/无线同机连接不误选另一台设备。
4. 在 Android 真机和模拟器分别安装；成功后进入主窗口应用详情；安装过程中关闭子窗口，确认最终设备状态与应用缓存更新。
5. 覆盖签名冲突、版本降级失败、安装时拔线均保留真实错误，已有应用不被自动卸载；刷新文件后才能安装替换后的 APK。

### 本次验证记录（2026-09-13）

- Rust 4 项测试、Dart/Widget 15 项测试均已通过；定向静态检查无问题。
- macOS arm64 Debug 与 Release 构建已通过，发布包内 helper 可直接解析仓库 APK；v1/v2/v3 证书、Info.plist 文件关联和内置许可证目录均已检查。`codesign --verify --deep --strict` 校验发布包通过。Intel 架构尚未构建验证。
- 定向 Flutter analyze 已通过；全仓 analyze 受原有 `test/apps_tab_filter_test.dart` 中 DeviceOverview 必填参数缺失、未定义 iOS 测试符号及既有 lint 阻断，未修改这些无关文件。
- Finder 实际打开、系统默认关联、跨窗口真实操作与真机安装尚未执行。
