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

  test('仅已确认的鸿蒙型号补充处理器名称', () {
    expect(
      HdcServiceDeviceInfo.formatProcessor('ADA-AL00U', '6 cores (arm64-v8a)'),
      'Kirin 9000SL · 6 cores (arm64-v8a)',
    );
    expect(
      HdcServiceDeviceInfo.formatProcessor('ADA-AL10U', '6 cores (arm64-v8a)'),
      '6 cores (arm64-v8a)',
    );
  });

  test('鸿蒙 WifiDevice 仅在已连接时返回当前 SSID', () {
    expect(
      HdcServiceDeviceInfo.parseWifiSsid('''
WiFi active state: activated
WiFi connection status: connected
  Connection.ssid: jie_5G
'''),
      'jie_5G',
    );
    expect(
      HdcServiceDeviceInfo.parseWifiSsid('''
WiFi connection status: disconnected
  Connection.ssid: old_network
'''),
      isNull,
    );
  });

  test('鸿蒙内核版本不包含构建编号与日期', () {
    expect(
      HdcServiceDeviceInfo.parseKernelVersion(
        'HarmonyOS localhost HongMeng Kernel 1.12.0 #1 SMP Wed Apr 15 07:57:02 UTC 2026 aarch64 Toybox',
      ),
      'HarmonyOS localhost HongMeng Kernel 1.12.0',
    );
  });
}
