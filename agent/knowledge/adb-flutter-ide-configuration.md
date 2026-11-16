# Flutter IDE 配置修复

## 问题与范围

Android Studio 安装 Flutter/Dart 插件后，仍需把 Flutter 自带 Dart SDK 绑定到 AnyDeck 主模块。CLI 可直接读取 `pubspec.yaml`，因此 CLI 能构建不代表 IDE 已配置好。

本次仅处理本机 `.idea`、配置恢复脚本与脚本测试，不调整业务代码、设备协议、窗口同步、主题或国际化。

## 配置恢复

关闭 AnyDeck 项目后执行：

```bash
python3 script/configure_flutter_ide.py --sdk /Users/mac/code_sdk/flutter
```

也可通过 `--project <项目根目录>` 指定另一份 AnyDeck checkout。脚本先验证项目入口与 SDK，再写入以下文件；原有文件首次修改前备份到 `.idea/.anydeck-backup/`。

| 文件 | 用途 |
| --- | --- |
| `.idea/AnyDeck.iml` | 主模块、lib/test 来源目录、Dart SDK 引用及生成目录排除 |
| `.idea/modules.xml` | 注册主模块，保留 Android Helper 等其他模块 |
| `.idea/libraries/Dart_SDK.xml` | 绑定 `<Flutter SDK>/bin/cache/dart-sdk` |
| `.idea/runConfigurations/AnyDeck.xml` | 从 `lib/main.dart` 启动主窗口，保留自定义参数和环境变量 |
| `.idea/runConfigurations/AnyDeck_No_Share_Core.xml` | 独立 Debug 入口，关闭文件互传服务与私有组件打包 |

`.idea` 继续保持 Git 忽略；提交恢复脚本和测试，不提交个人 SDK 路径、workspace 状态或缓存。脚本使用 Python 标准库，不安装插件、不启动 App，也不修改 Flutter SDK。

## 路径与依赖机制

- 当前 IntelliJ `PathMacroUtil.getModuleDir` 会特殊处理 `.idea` 内的 `.iml`：`$MODULE_DIR$` 已是项目根目录，不应追加 `/..`。
- `.iml` 使用 `file://$MODULE_DIR$`；`modules.xml` 与运行入口继续使用 `$PROJECT_DIR$`。本机 Preview 的模块配置未展开 `$PROJECT_DIR$` 时，会导致 Flutter 插件找不到 `main.dart` 所属模块。
- Dart SDK 使用 project-level `Dart SDK` library，由主模块 `orderEntry` 引用。Flutter 插件可据此推导 Flutter SDK，无需创建额外的 SDK XML 字段。
- AnyDeck 运行入口附加 `--no-pub`，复用已准备的依赖。IDE 继承的 `PUB_HOSTED_URL` 若与锁文件 hosted URL 不同，默认自动 `pub get` 可能重新解析依赖；需要更新依赖时应显式执行 `flutter pub get` 并检查锁文件差异。
- 重新打开项目后，在 Flutter 目标选择器选择 **macOS (desktop)**，再运行 **AnyDeck**。设备选择由插件管理，不写入无效的 `selectedDeviceId` XML 字段。

本机 Cargo 缓存来自 `rsproxy`，默认 crates.io registry 的缓存不完整。为避免原生构建等待网络，本机运行入口额外设置 `CARGO_NET_OFFLINE=true`，并把 `CARGO` 指向 `.idea/anydeck-cargo.sh`。这个本机 wrapper 复用原 Cargo，只补 source replacement：

```sh
#!/bin/sh
exec "$HOME/.cargo/bin/cargo" --config 'source.crates-io.replace-with="rsproxy"' --config 'source.rsproxy.registry="sparse+https://rsproxy.cn/index/"' "$@"
```

启用离线模式前须确保当前架构依赖已缓存；恢复脚本保留这些自定义环境变量，不将 registry 偏好强加给其他机器。

Flutter 98 的环境变量写在 `<option name="envs">` 下，每项使用 `<entry key="变量名" value="值" />`；不增加 `<map>` 外层。建议通过 Run Configuration 的 Environment variables 字段保存，避免配置被插件忽略。

## 旧模块缓存

修改磁盘 `.iml` 后，IDE 可能继续读取旧 workspace model。若仍出现 `FlutterApp.addToEnvironment` 的 `app must not be null`，先检查 `idea.log` 中的模块路径和 `Load workspace model from cache`，再关闭 AnyDeck，仅备份重命名该项目的 `project-model-cache` 目录。

本机路径为：

```text
~/Library/Caches/Google/AndroidStudio2026.2.3/projects/anydeck.6138961c/project-model-cache/
```

版本目录和项目 hash 因机器而异，应从当前日志确认；无需清理其他项目或全局缓存。

## 回归与验收

```bash
python3 -m unittest test/script/test_flutter_ide_config.py -v
flutter analyze --no-pub
```

自动回归覆盖标准模块、遗留宏修复、真实根目录展开、SDK 路径 XML 转义、保留子模块和运行参数、幂等、首次备份，以及缺失入口、损坏或未知配置时不写入。IDE 验收检查 Dart SDK 未配置提示消失、macOS 目标可选，并从 Run 启动构建和主窗口。

本次脚本回归 11 项通过。全项目静态分析无 error，仍有既有 5 项 warning、721 项 info，未修改无关业务代码消除这些提示。

本机 IDE 已能识别 `main.dart` 所属 AnyDeck 模块，并从 Run 进入 Dart、Swift 与 Rust 原生构建。完整包仍要求 `script/share_core.lock.json` 对应的私有制品；仅有 SDK 和运行配置不代表该制品已齐备。当前固定 commit `b6ccfbd244eec0a908c80a91c228995b15581b10` 未发布到远端，本机未命中校验缓存时会因私有制品获取失败而终止，不能将此归因于 Dart 路径，也不能用旧版本 zip 替代。

## 不含 Share Core 的独立 Debug 入口

为缺少私有制品的开发环境新增 **AnyDeck（不含 Share Core）**。执行上面的配置恢复命令后，Android Studio 选择该入口与 **macOS (desktop)**；本机已生成并选中该配置。完整入口 **AnyDeck** 继续保留私有制品校验，两者不互相修改开关。

| 层次 | 开关与行为 |
| --- | --- |
| Flutter | `--debug --no-pub --dart-define=ANYDECK_ENABLE_SHARE_CORE=false`；隐藏文件互传侧栏/页面，不创建服务和互传通知监听，旧互传链接重定向到设备列表 |
| Xcode 构建 | `ANYDECK_SKIP_SHARE_CORE=1`；Debug 跳过 Share Core 安装器，不访问私有源码仓库或制品，不读取失效的 archive 路径 |
| 增量包清理 | 仅移除当前目标 `.app/Contents/MacOS/ShareCore` 和 `Contents/Resources/ShareCore`，包含旧程序和 manifest，随后仍由 Xcode 签名 |

不含 Share Core 指不获取、编译或打包私有原生组件；主仓公开的 IPC 适配与完整入口继续保留。编译期开关由同一快照供所有窗口使用，不通过设置或跨窗口广播动态切换。该入口仅用于 Debug，Release/Profile 仍禁止跳过私有组件。

CLI 使用同一组开关，构建后还会检查最终包内无上述目录：

```bash
./script/build_macos_without_share_core.sh
```

Flutter 不在 PATH 时可设置 `FLUTTER_BIN=/Users/mac/code_sdk/flutter/bin/flutter`。本机 CLI 验证还复用了既有 `.idea/anydeck-cargo.sh` 与离线缓存；IDE 独立入口自动继承完整入口的 `CARGO` 等工具链环境，并保留自己的自定义参数。首次生成时克隆完整配置，后续只补缺失环境并校正 Debug/Share Core 开关；两份入口均先验证 XML，再备份写入。

### 影响与验证

直接影响配置生成、Share Core 打包及文件互传导航；不修改 ADB/HDC、投屏、设备管理和主题/语言实现。相关测试覆盖中英文、明暗主题、默认服务入口保留、禁用时不读取服务 Provider、深链接回退、两类残留目录、错误路径与符号链接、失败退出码和原配置保留。新 Dart 文件与调整后的主文件均小于 500 行。

```bash
python3 -m unittest test/script/test_build_without_share_core.py test/script/test_embed_share_core.py test/script/test_flutter_ide_config.py -v
flutter test --no-pub test/no_share_core_build_test.dart test/dashboard_service_navigation_test.dart test/dashboard_route_test.dart
flutter test --no-pub --dart-define=ANYDECK_ENABLE_SHARE_CORE=false test/no_share_core_build_test.dart
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
```

本轮 27 项脚本、默认配置 18 项 Flutter 与禁用配置 5 项 Flutter 测试通过。全项目分析 0 error、5 warning、723 info；定向分析无 error/warning，仅 5 项 Flutter SDK 弃用提示。CLI 实际构建 `build/macos/Build/Products/Debug/AnyDeck.app` 成功，包内两个 Share Core 目录均不存在，`codesign --verify --deep --strict` 通过。IDE 已识别并选中新入口；本轮未启动 App、未操作手机，不将构建验证描述为真机功能验收。开始时已有的 7 个依赖锁/插件生成文件修改保持逐字不变，不纳入本次提交。
