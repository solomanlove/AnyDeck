import 'package:any_deck/core/harmony/harmony_foreground_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析 HarmonyOS 前台页面的友好字段', () {
    const dump = '''
focusWindowId: 42
bundleName: com.huawei.hmos.settings
abilityName: com.huawei.hmos.settings.MainAbility
pageName: pages/wifi/WifiPage
windowName: SettingsWindow
''';

    final window = HarmonyForegroundWindow.parse(dump);

    expect(window.bundleName, 'com.huawei.hmos.settings');
    expect(window.abilityName, 'com.huawei.hmos.settings.MainAbility');
    expect(window.pageName, 'pages/wifi/WifiPage');
    expect(window.windowName, 'SettingsWindow');
  });

  test('缺少结构化字段时从 component 提取 Bundle 与 Ability', () {
    final window = HarmonyForegroundWindow.parse(
      'focused: com.example.demo/com.example.demo.EntryAbility',
    );

    expect(window.bundleName, 'com.example.demo');
    expect(window.abilityName, 'com.example.demo.EntryAbility');
  });
}
