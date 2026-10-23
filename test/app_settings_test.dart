import 'package:any_deck/app/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSettings 投屏控制栏设置', () {
    test('默认使用自动隐藏', () {
      const settings = AppSettings();

      expect(settings.mirrorControlsAlwaysVisible, isFalse);
    });

    test('copyWith 可以开启始终显示并保留其他设置', () {
      const settings = AppSettings(scrcpyAlwaysOnTop: false);

      final updated = settings.copyWith(mirrorControlsAlwaysVisible: true);

      expect(updated.mirrorControlsAlwaysVisible, isTrue);
      expect(updated.scrcpyAlwaysOnTop, isFalse);
    });
  });

  test('DLNA 名称默认值与 copyWith 保留其他设置', () {
    const settings = AppSettings(airplayServerName: '卧室 AirPlay');
    final updated = settings.copyWith(dlnaServerName: '客厅电视');

    expect(settings.dlnaServerName, AppSettings.defaultDlnaServerName);
    expect(updated.dlnaServerName, '客厅电视');
    expect(updated.airplayServerName, '卧室 AirPlay');
  });
}
