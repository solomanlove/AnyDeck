# AnyDeck 多机开发工具链统一

## 需求与设计

2026-11-18：Flutter 升级至 stable 3.50.0，统一多机 Flutter、Rust、CocoaPods 和 CI，保留已有无关修改。开发者命令的权威说明见 [DEVELOPMENT.md](../../DEVELOPMENT.md)。

此前 CI 固定 Flutter 3.47.2，本机使用独立 SDK 和 Homebrew Rust 1.95.0；Rust/CocoaPods 未由仓库配置统一。个人 Pub 镜像、IDE Cargo wrapper 和 Flutter Debug 补丁可能导致相同源码使用不同环境。

## 关键实现

- `.fvmrc` 是 Flutter 版本唯一来源，3.50.0 附带 Dart 3.14.0；`pubspec.yaml` 表达兼容范围。
- `rust-toolchain.toml` 固定 Rust/Cargo 1.95.0；通过 rustup `which --toolchain` 获取实际 Cargo，同时指定同目录 rustc，避免 Homebrew PATH 或个人 override 选择其他编译器。
- `Gemfile` 固定 CocoaPods 1.16.2；`Gemfile.lock` 固定 transitive gems / Bundler 2.6.9。`bundle exec` 将 Flutter 及其 pod 子进程放入同一环境。
- Ruby 3.4+ 的 `kconv` 已从默认库移出，补充固定 `nkf 0.2.0`，避免仅 `pod --version` 正常、生成 Pods 工程时 CFPropertyList 才加载失败；环境检查实际加载该依赖。
- `setup_dev.sh` 准备工具与锁定依赖；`check_env.sh` 检查版本、SDK 修改、Rust target、gems、Xcode 和原生库，只有 `--share-core` 可获取私有制品。
- 初始化通过 `--config-only` 刷新旧 SDK 的 xcconfig/SPM 引用，不编译 App；对 Podfile.lock 做内容保护，意外变化恢复并失败。随后在 `macos/` 目录执行 `pod install --deployment`，避免 CocoaPods 的相对 Swift Package 路径从仓库根目录解析错误。
- Flutter 构建调用统一入口，两份 Rust 构建均使用 `--locked`。IDE 使用相同 SDK 与 bundle 环境，仅写入忽略目录并保留运行参数。
- CI 读取仓库版本文件，保留双架构、私有制品和发布验证。本次不触发远端 workflow 或发布新版本。

## 兼容边界

新基线不自动应用 3.47.2 的 Flutter tools 补丁；环境检查拒绝未管理的 tools/engine 修改。旧脚本保留用于历史版本排查。

Homebrew 库与 Xcode 尚未严格锁版本，检查输出实际版本。Intel 原生构建、设备功能和 UI 验收需分别验证。原有业务与插件注册文件修改不属于本次迁移。

## 验证记录

2026-11-18，本机实际验证：

| 项目 | 结果 |
| --- | --- |
| Flutter SDK | stable 3.50.0 / Dart 3.14.0，revision `ab2912035e160d9cad6306df307576da6128ebdb`，未修改 SDK 源码 |
| SDK 下载校验 | arm64 官方 manifest SHA-256 `ed2d08a3e3c023e84cbe9316d21bd88fda6ee9552f90c1eb4da41a07c170fb35` 一致 |
| Rust / CocoaPods | rustup 1.95.0 的 Cargo/rustc；CocoaPods 1.16.2 / Bundler 2.6.9，Ruby 4.0.2 |
| 系统依赖 | Xcode 26.3 / 17C529，OpenSSL 3.6.2，libplist 2.7.0 |
| 初始化 | `setup_dev.sh --skip-native --ide` 全流程及重复执行通过；Pods deployment、两个 IDE 环境和 `check_env.sh` 通过 |
| 脚本回归 | 101 项通过，包含 19 项工具链选择、版本漂移、锁保护、参数转发和 IDE 保留测试 |
| Rust | 两个 crate 的 `cargo check --locked --offline` 均通过 |
| Flutter 静态分析 | 无 error；5 warning / 875 info，使用不将 warning/info 作为 fatal 的检查命令通过，未改无关业务代码消除提示 |
| Flutter 聚焦测试 | no-share 开关、主窗口路由和 outbox 服务 17 项通过；禁用 Share Core 的编译开关模式另 5 项通过 |
| macOS 实际编译 | 不含 Share Core 的 Debug 构建通过，arm64 和整包签名校验通过；未启动 App |

首次工具链提交 `cf077ad` 时，全量 Flutter 测试未全绿：2522 项通过、9 项跳过、60 项失败；另有 `tab_order_consistency_test.dart` 挂起，在新旧 SDK 均复现后主动中止。失败中 59 项在保留升级前工作区的 Flutter 3.47.2 对照目录中复现；剩余 outbox `continue` 用例单独重跑通过。既有失败包含已失效的设备行双击 finder、旧页面文案/颜色断言、SharedPreferences mock 缺失和 UDP 端口释放问题；该提交仅处理环境，后续修复见 [Flutter 测试隔离与异步回归](adb-flutter-test-isolation.md)。

首次工具链提交的 Pub 依赖在仓库锁文件上使用新 SDK `--enforce-lockfile` 验证通过，无需升级其他业务包；仅将 Flutter test SDK 要求的 `test_api` 对齐为 0.7.14。原有 hosted URL、cupertino_ui 和 material_ui 工作区修改保留且不纳入提交。Podfile.lock 的 CocoaPods 版本标记对齐 1.16.2 属于环境锁定，其余内容保留。

Intel/Windows/Linux、完整 Share Core Release、手机功能和远端 CI 未在本机重新执行。原 arm64e destination 问题在本机新 SDK 构建中未出现，旧补丁不应用于新 SDK。

## 后续测试修复验证

2026-11-18，按用户要求继续修复失败及挂起测试，具体原因和维护约定见 [测试修复记录](adb-flutter-test-isolation.md)。未新增 skip，也未提高生产环境超时。

| 项目 | 结果 |
| --- | --- |
| 工作区全量 Flutter 测试 | 2588 项通过、9 项按既有条件跳过；0 失败、0 挂起，正常退出 |
| 工作区静态分析 | 0 error、5 项既有 warning、875 info；按项目门禁命令通过 |
| 独立提交快照全量测试 | 使用仓库 Pub 锁文件并从源码编译 Rust 库后，2588 项通过、9 项既有条件跳过；0 失败、0 挂起，约 223s 正常退出 |
| 独立提交快照静态分析 | 0 error、5 项既有 warning、874 info；按项目门禁命令通过 |
| 平台与异步专项 | WDA 恢复 5 项、UDP 关闭/重新发布 8 项均通过；完整回归包含这些用例 |
| 摄像头隔离 | 7 项通过，版本拒绝与取消用例显式注入 mock bridge，并验证不会启动原生会话 |
| 脚本与工具链 | 101 项脚本回归、`check_env.sh` 与 workflow YAML 解析通过 |

独立提交快照最初暴露了本机 Rust 构建缓存掩盖的问题：两个摄像头用例未注入 mock；另两个 DAL 可用性断言确实需要原生库。已修复前者，并为全量回归补齐 `build_device_bridge.sh` 前置步骤；后者保留真实原生集成断言。快照使用仓库原有 Pub 锁文件，Rust 库由快照源码和锁定 Cargo 编译，不复制工作区预编译产物。

原有跳过项依赖真机、原生动态库、官方 MCP SDK 或 Windows 平台。远端 CI 已增加 Flutter 静态分析与全量测试门禁，尚未触发 workflow；本地测试通过不替代设备与发布验收。
