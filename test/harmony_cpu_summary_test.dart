import 'package:any_deck/core/harmony/hdc_service_device_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('鸿蒙 CPU 概要优先使用 ABI，参数失败时回退系统架构', () {
    expect(
      HdcServiceDeviceInfo.parseCpuSummary('6\narm64-v8a\naarch64\n'),
      '6 cores (arm64-v8a)',
    );
    expect(
      HdcServiceDeviceInfo.parseCpuSummary(
        '6\nGet parameter "const.product.cpu.abilist" fail! errNum is:106!\naarch64\n',
      ),
      '6 cores (aarch64)',
    );
    expect(
      HdcServiceDeviceInfo.parseCpuSummary('invalid\naarch64\n'),
      isNull,
    );
  });
}
