import 'package:any_deck/core/device_info/android_version_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
