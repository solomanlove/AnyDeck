# AnyDeck 产品体验问题修复（2026-10-31）

依据 2026-10-30 黑盒体验表 AD-001～AD-013 修改。表中的锁屏、HDC 无目标与服务发现无响应属于验收环境记录，不据此修改产品功能。

## AD-001、AD-013：手动连接表单

- 旧弹窗在 `showDialog` 返回后立即释放 `TextEditingController`，退出动画期间输入框可能仍引用该控制器；地址也未校验。新 `TcpipConnectionDialog` 由 State 持有控制器，随 Route 卸载释放。
- 统一校验 IP/主机名和 1～65535 端口，省略端口默认 5555；无效输入留在表单内，不调用连接服务。连接中禁用提交，失败保留输入、显示错误并允许重试，关闭后晚到结果不再访问界面。
- 不预填一个看似真实的地址；示例只放在 hint 中。先展示输入与准备提示，Android、HarmonyOS 和排障指南分别折叠。指南与新提示均提供中英文并使用当前 Theme。
- 保留现有 `connectNetworkDevice` 的 ADB/HDC 连接、注册表刷新和命令超时机制；不新增后台进程、多窗口广播或投屏参数修改。

### 验证与交接

- `flutter test --no-pub test/tcpip_connection_dialog_test.dart`：7 项通过，覆盖非法地址、有效输入、中文/英文、明暗主题、退出动画、失败后重试入口、防重复和关闭后的迟到错误。
- 定向 `flutter analyze --no-pub`：无新增诊断。共享入口保留两个既有 `unused_element`（`_restartAdbServer`、`_openLocalTerminal`），HEAD 中也只有声明，无关代码未改动。
- 未启动项目或操作真机。需在运行包复核 `invalid:abc` 就地报错、有效地址失败后重试，以及现有投屏不受弹窗退出影响。自动测试不能代替 Release/真机验收。
