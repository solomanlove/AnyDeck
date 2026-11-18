# AnyDeck 开发环境

## 工具链基线

| 工具 | 权威配置 | 要求 |
| --- | --- | --- |
| Flutter | `.fvmrc` | stable 3.50.0，使用随 SDK 提供的 Dart 3.14.0 |
| Rust / Cargo | `rust-toolchain.toml` | 1.95.0，minimal + rustfmt/clippy |
| CocoaPods | `Gemfile` / `Gemfile.lock` | 1.16.2，Bundler 2.6.9 |
| macOS 原生库 | `Brewfile` | pkgconf、OpenSSL 3、libplist ≥ 2.3 |
| 私有组件 | `script/share_core.lock.json` | 固定 commit、架构和 SHA-256 |

自动初始化目前支持 macOS Apple Silicon / Intel。预先安装完整 Xcode、Command Line Tools、Python 3、Homebrew 和 [FVM](https://fvm.app/documentation/getting-started/installation)，完成 Xcode 首次启动与许可确认。Windows、Linux 的初始化和原生构建未在这次迁移中验证。

## 初始化与检查

```bash
# 新电脑：安装工具链，按锁文件获取 Pub/Cargo/Pods 依赖
./script/setup_dev.sh

# 同时更新本机 Android Studio 的 SDK 与两个 AnyDeck 运行入口
./script/setup_dev.sh --ide

# 已准备原生依赖时跳过 Homebrew 安装
./script/setup_dev.sh --skip-native

# 默认检查不下载依赖、不构建、不启动 App
./script/check_env.sh

# 额外校验完整包的私有组件，可能下载制品，需要只读仓库权限
./script/check_env.sh --share-core
```

初始化不修改全局 shell 配置，不卸载已有 SDK。使用 `pub get --enforce-lockfile`、`cargo fetch --locked`、`pod install --deployment` 和 Bundler frozen，锁不匹配直接失败，不升级业务依赖。Share Core 不属于默认初始化依赖。

## CLI 与 IDE

```bash
./script/flutter.sh --version
./script/flutter.sh analyze --no-pub --no-fatal-infos --no-fatal-warnings
./script/flutter.sh test --no-pub
./script/dev_exec.sh cargo check --locked --manifest-path rust/device_bridge/Cargo.toml

# 完整 Release，需要 Share Core 私有制品
./script/build_macos.sh

# 仅构建 Debug，不获取私有组件、不启动 App
./script/build_macos_without_share_core.sh
```

`flutter.sh` / `dev_exec.sh` 选择 `.fvm/flutter_sdk`，通过 rustup 定位固定 Cargo/rustc，通过固定 Bundler 执行命令，让 Flutter 调用的 `pod` 使用同一 Gemfile。构建脚本默认调用统一入口；显式受控环境仍可使用 `FLUTTER_BIN` / `CARGO`，应先执行环境检查。

直接运行全局 `flutter` / `cargo` 仍可能使用其他项目的版本。日常开发使用以上项目入口，切换 SDK 后重新打开 IDE。

IDE 的 Flutter SDK 使用 `.fvm/flutter_sdk`，Dart SDK 使用其 `bin/cache/dart-sdk`。`setup_dev.sh --ide` 复用配置恢复工具，保留运行参数，只替换工具链环境和旧 Cargo wrapper / 离线开关。两个运行入口的环境来自 `bundle exec env` 的工具链字段白名单，不保存凭据。本机配置位于 Git 忽略的 `.idea/`。

## 依赖源、架构与补丁

- 入口从 `pubspec.lock` 读取 hosted 源，覆盖个人 `PUB_HOSTED_URL`，避免镜像差异改写锁文件。个人代理、registry 凭据和缓存目录不提交。
- 可按本机网络设置 `FLUTTER_STORAGE_BASE_URL` / `RUSTUP_DIST_SERVER`。FVM 下载失败时，可从 [Flutter 官方归档](https://docs.flutter.dev/install/archive) 下载相同版本与架构的 SDK，校验官方 manifest 的 SHA-256 后放入 FVM cache，再初始化。
- Flutter、Pods 与 Rust 默认使用宿主架构；指定 `ANYDECK_TARGET_ARCH=arm64` 或 `x86_64` 时需准备对应 Rust target 和原生库。各电脑独立生成缓存，不复制 `build/`、Pods、Rust target 或 `.fvm/`。
- 新基线使用原始 Flutter 3.50.0，检查拒绝未管理的 Flutter tools / engine 配置修改。历史 `fix_flutter_macos_debug.py` 针对 3.47.2 的 arm64e 问题保留，不自动应用到新 SDK；出现新错误时应先定位，再维护对应补丁与回归。
- `Brewfile` 固定依赖名称，未锁瓶装库版本；Xcode 与系统 SDK 仍由电脑/Runner 提供。检查输出实际版本，此方案不保证不同系统构建产物逐字节相同。

## CI 与升级验证

macOS Release workflow 读取同一 `.fvmrc`、`rust-toolchain.toml` 和 `Gemfile.lock`，保留原有 arm64 / Intel matrix、私有制品与发布门禁。

```bash
python3 -m unittest discover -s test/script -v
./script/check_env.sh
./script/flutter.sh analyze --no-pub --no-fatal-infos --no-fatal-warnings
./script/flutter.sh test --no-pub
```

升级时修改权威版本配置，单独解析并审核必要的锁文件差异。普通初始化只消费已有锁文件。`.fvm/`、`.bundle/`、`vendor/bundle/` 与 IDE 配置不提交。

静态分析命令保留 warning/info 输出，仅以 error 判定失败；本次迁移存在的既有 lint 和全量测试失败、旧 SDK 对照结果见 [知识库验证记录](agent/knowledge/adb-development-toolchain.md)。
