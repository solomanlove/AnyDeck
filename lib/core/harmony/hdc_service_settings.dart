import '../adb/adb_result.dart';
import 'hdc_service.dart';

/// HarmonyOS Settings 支持的快捷入口。
enum HarmonySettingsPage { main, developer, wifi, deviceInfo, locale, apps }

extension HdcServiceSettings on HdcService {
  /// 按屏幕宽高从左/右状态栏下拉，分别打开通知中心与控制中心。
  Future<AdbResult> openSystemPanel(
    String deviceId, {
    required bool quickSettings,
  }) async {
    final display = await shell(
      deviceId,
      'hidumper -s DisplayManagerService -a -a',
    );
    final size = RegExp(
      r'\bWidth:\s*(\d+)\s*\n\s*Height:\s*(\d+)',
    ).firstMatch(display.stdout);
    final width = int.tryParse(size?.group(1) ?? '');
    final height = int.tryParse(size?.group(2) ?? '');
    if (!display.isSuccess || width == null || height == null ||
        width < 200 || height < 400) {
      return const AdbResult(
        exitCode: 1,
        stdout: '',
        stderr: '无法读取鸿蒙屏幕尺寸',
      );
    }
    final x = (width * (quickSettings ? 0.9 : 0.1)).round();
    final startY = (height * 0.02).round();
    final endY = (height * 0.35).round();
    return shell(deviceId, 'uinput -T -m $x $startY $x $endY 300');
  }

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
        'aa start -a $bundle.MainAbility -b $bundle',
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
