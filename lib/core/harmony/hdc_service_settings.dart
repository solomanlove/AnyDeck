import '../adb/adb_result.dart';
import 'hdc_service.dart';

/// HarmonyOS Settings 支持的快捷入口。
enum HarmonySettingsPage { main, developer, wifi, deviceInfo, locale, apps }

extension HdcServiceSettings on HdcService {
  /// 使用公开 Want action 跳转具体设置页，不支持时回退 Settings 首页。
  Future<AdbResult> openSettings(
    String deviceId,
    HarmonySettingsPage page,
  ) async {
    final action = switch (page) {
      HarmonySettingsPage.wifi => 'ohos.settings.wireless',
      HarmonySettingsPage.apps => 'ohos.settings.manage.applications',
      _ => null,
    };
    if (action != null) {
      final result = await shell(deviceId, 'aa start -A $action');
      if (result.isSuccess) return result;
    }

    // 华为商用系统与 OpenHarmony 标准系统的 Settings bundle 不同，依次兼容。
    for (final bundle in const [
      'com.huawei.hmos.settings',
      'com.ohos.settings',
    ]) {
      final result = await shell(
        deviceId,
        'aa start -a MainAbility -b $bundle',
      );
      if (result.isSuccess) return result;
    }
    return const AdbResult(
      exitCode: 1,
      stdout: '',
      stderr: 'HarmonyOS Settings 页面启动失败',
    );
  }
}
