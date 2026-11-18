import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/core/adb/adb_environment_service.dart';
import 'package:any_deck/core/receiver/receiver_identity.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:any_deck/core/providers/host_network_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/src/internals.dart' show Override;

/// 导航与应用 UI 测试只读取设置快照，不初始化登录项、接收端或原生广播。
class DashboardTestSettings extends AppSettingsController {
  @override
  AppSettings build() => const AppSettings();
}

/// 固定可用的 ADB 环境，避免根页面在 FakeAsync 中启动真实 CLI 检测。
class DashboardTestAdbEnvironment extends AdbEnvironmentNotifier {
  @override
  AdbEnvironmentInfo build() =>
      const AdbEnvironmentInfo(status: AdbEnvironmentStatus.ready);

  @override
  Future<void> checkAndPromptIfNeeded(BuildContext context) async {}
}

/// 导航断言不探测本机网卡，避免真实 IO 的超时 Timer 残留到用例结束。
class _HostNetwork extends HostNetworkNotifier {
  @override
  Future<HostNetworkInfo> build() async => const HostNetworkInfo();
}

/// 仅隔离平台初始化；设备、页面路由和业务 Provider 继续由用例单独装配。
List<Override> dashboardTestPlatformOverrides() => [
  appSettingsProvider.overrideWith(DashboardTestSettings.new),
  adbEnvironmentProvider.overrideWith(DashboardTestAdbEnvironment.new),
  hostNetworkProvider.overrideWith(_HostNetwork.new),
  receiverIdentityProvider.overrideWith(
    (ref) async => const ReceiverIdentity(
      uuid: '00000000-0000-4000-8000-000000000001',
      computerName: 'Test Mac',
    ),
  ),
];
