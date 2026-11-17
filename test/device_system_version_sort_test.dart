import 'package:any_deck/core/providers/modules/registered_device_model.dart';
import 'package:any_deck/features/devices/model/device_system_version_sort.dart';
import 'package:flutter_test/flutter_test.dart';

/// 版本排序只消费展示值，覆盖真实三平台格式与数字比较边界。
RegisteredDevice _device(String? version) => RegisteredDevice(
  id: 'version-device',
  status: 'device',
  isOnline: true,
  androidVersion: version,
);

int _compare(String? a, String? b, {bool ascending = true}) =>
    DeviceSystemVersionSort.compare(
      _device(a),
      _device(b),
      ascending: ascending,
    );

void main() {
  test('AnyDeck Android 版本按数字而非字符排序，API 为次级数字', () {
    expect(_compare('Android 9 (API 28)', 'Android 10 (API 29)'), lessThan(0));
    expect(_compare('Android 15 (API 35)', 'Android 17 (API 37)'), lessThan(0));
    expect(
      _compare('Android 12 (API 31)', 'Android 12L (API 32)'),
      lessThan(0),
    );
    expect(_compare('Android 15 (API 9)', 'Android 15 (API 10)'), lessThan(0));
    expect(
      _compare('Android 17 (API 37)', 'Android 15 (API 35)', ascending: false),
      lessThan(0),
    );
  });

  test('AnyDeck iOS 和 OpenHarmony 的点分版本逐段比较', () {
    expect(_compare('iOS 15.8.9', 'iOS 15.8.10'), lessThan(0));
    expect(_compare('iOS 15.9', 'iOS 15.10'), lessThan(0));
    expect(
      _compare(
        'OpenHarmony-6.1.0.9 (API 23)',
        'OpenHarmony-6.1.0.115 (API 23)',
      ),
      lessThan(0),
    );
    expect(_compare('iOS 18', 'iOS 18.0'), 0);
    expect(_compare('iOS 018.00.0', 'ios 18'), 0);
    expect(_compare('OpenHarmony-6.1.0.115', 'OpenHarmony 6.1.0.115'), 0);
    expect(
      _compare('OpenHarmony_6.1.0.9', 'OpenHarmony 6.1.0.115'),
      lessThan(0),
    );
  });

  test('AnyDeck 只有 API 的 HarmonyOS 也能比较，未知版本始终置底', () {
    expect(
      _compare('HarmonyOS NEXT (API 23)', 'HarmonyOS NEXT (API 24)'),
      lessThan(0),
    );
    for (final unknown in [null, '', '  ', '-', 'HarmonyOS NEXT', 'iOS']) {
      for (final ascending in [true, false]) {
        expect(
          _compare(unknown, 'Android 17 (API 37)', ascending: ascending),
          greaterThan(0),
        );
        expect(
          _compare('iOS 15.8.8', unknown, ascending: ascending),
          lessThan(0),
        );
      }
    }
    expect(_compare(null, '-'), 0);
  });

  test('AnyDeck 不同系统名称排序确定，忽略大小写和首尾空白', () {
    expect(_compare(' Android 15 (API 35) ', 'android 15 (API 35)'), 0);
    expect(_compare('Android 17 (API 37)', 'HarmonyOS 6'), lessThan(0));
    expect(_compare('HarmonyOS 6', 'iOS 15.8.8'), lessThan(0));
    expect(
      _compare('Android 17 (API 37)', 'HarmonyOS 6', ascending: false),
      greaterThan(0),
    );
  });

  test('AnyDeck 厂商系统与预览版数字可自然比较且不会溢出', () {
    expect(
      _compare('HyperOS OS1.0.9.0.TLDCNXM', 'HyperOS OS1.0.10.0.TLDCNXM'),
      lessThan(0),
    );
    expect(
      _compare('Android 17 Beta 2 (API 37)', 'Android 17 Beta 10 (API 37)'),
      lessThan(0),
    );
    expect(
      _compare(
        'iOS 999999999999999999999999999999.9',
        'iOS 999999999999999999999999999999.10',
      ),
      lessThan(0),
    );
  });

  test('AnyDeck 排序不读取 SDK 缓存并让相同版本由调用方稳定兜底', () {
    final a = _device('Android 15 (API 35)').copyWith(id: 'a', sdkVersion: 100);
    final b = _device('Android 15 (API 35)').copyWith(id: 'b', sdkVersion: 1);
    expect(DeviceSystemVersionSort.compare(a, b), 0);
    expect(DeviceSystemVersionSort.compare(a, b, ascending: false), 0);
  });
}
