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
}
