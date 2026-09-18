import 'package:any_deck/core/device_info/android_version_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AndroidVersionHelper.formatApiLevel', () {
    test('应用详情的 API 21 与 29 对应实际 Android 版本', () {
      expect(AndroidVersionHelper.formatApiLevel(21), 'Android 5.0 (API 21)');
      expect(AndroidVersionHelper.formatApiLevel(29), 'Android 10 (API 29)');
    });

    test('区分小版本、Wear 版本及新版本', () {
      expect(AndroidVersionHelper.formatApiLevel(20), 'Android 4.4W (API 20)');
      expect(AndroidVersionHelper.formatApiLevel(27), 'Android 8.1 (API 27)');
      expect(AndroidVersionHelper.formatApiLevel(32), 'Android 12L (API 32)');
      expect(AndroidVersionHelper.formatApiLevel(37), 'Android 17 (API 37)');
    });

    test('缺失和未知 API 不伪造 Android 版本', () {
      expect(AndroidVersionHelper.formatApiLevel(null), '-');
      expect(AndroidVersionHelper.formatApiLevel(99), 'API 99');
    });
  });

  group('AndroidVersionHelper.getCustomOsVersion', () {
    test('识别 HyperOS 并保留版本', () {
      final properties = AndroidVersionHelper.parseGetProp(
        '[ro.mi.os.version.name]: [OS2.0.1.0]\n'
        '[ro.build.version.release]: [15]\n',
      );

      expect(
        AndroidVersionHelper.getCustomOsVersion(properties),
        'HyperOS OS2.0.1.0',
      );
    });

    test('识别 EMUI 并清理属性前缀', () {
      expect(
        AndroidVersionHelper.getCustomOsVersion({
          'ro.build.version.emui': 'EmotionUI_14.2.0',
        }),
        'EMUI 14.2.0',
      );
    });

    test('已有系统名称时不重复拼接', () {
      expect(
        AndroidVersionHelper.getCustomOsVersion({
          'ro.vivo.os.name': 'OriginOS',
          'ro.vivo.os.version': 'OriginOS 5',
        }),
        'OriginOS 5',
      );
    });

    test('原生 Android 属性不误判为厂商系统', () {
      expect(
        AndroidVersionHelper.getCustomOsVersion({
          'ro.build.version.release': '16',
          'ro.product.brand': 'Google',
        }),
        isNull,
      );
    });
  });
}
