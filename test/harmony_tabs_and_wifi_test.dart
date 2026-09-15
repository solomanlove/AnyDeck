import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/harmony/harmony_mirror_service.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHdcServiceForTest extends HdcService {
  _FakeHdcServiceForTest() : super(executable: 'hdc');

  final List<List<String>> executedRuns = [];
  final List<String> executedShells = [];

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    executedRuns.add(args);
    return const AdbResult(exitCode: 0, stdout: 'Connect OK', stderr: '');
  }

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    executedShells.add(command);
    if (command.contains('ifconfig wlan0')) {
      return const AdbResult(
        exitCode: 0,
        stdout: '''wlan0     Link encap:Ethernet  HWaddr 12:34:56:78:9a:bc
          inet addr:192.168.3.45  Bcast:192.168.3.255  Mask:255.255.255.0
          inet6 addr: fe80::1234/64 Scope:Link
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1''',
        stderr: '',
      );
    }
    return const AdbResult(exitCode: 0, stdout: 'success', stderr: '');
  }
}

void main() {
  group('HDC Wireless Debugging Tests', () {
    late _FakeHdcServiceForTest hdc;

    setUp(() {
      hdc = _FakeHdcServiceForTest();
    });

    test('enableTcpMode sends hdc -t <id> tmode port <port>', () async {
      final res = await hdc.enableTcpMode('device_123', port: 5555);
      expect(res.isSuccess, isTrue);
      expect(hdc.executedRuns.last, ['-t', 'device_123', 'tmode', 'port', '5555']);
    });

    test('connectWireless sends hdc tconn <address>', () async {
      final res = await hdc.connectWireless('192.168.3.45:5555');
      expect(res.isSuccess, isTrue);
      expect(hdc.executedRuns.last, ['tconn', '192.168.3.45:5555']);
    });

    test('disconnectWireless sends hdc tconn <address> -remove', () async {
      final res = await hdc.disconnectWireless('192.168.3.45:5555');
      expect(res.isSuccess, isTrue);
      expect(hdc.executedRuns.last, ['tconn', '192.168.3.45:5555', '-remove']);
    });

    test('getDeviceIp parses IP from ifconfig wlan0 output', () async {
      final ip = await hdc.getDeviceIp('device_123');
      expect(ip, '192.168.3.45');
    });

    test('parseIpFromIfconfig handles inet and inet addr variations', () {
      expect(
        HdcService.parseIpFromIfconfig('inet addr:10.0.0.12  Bcast:10.0.0.255'),
        '10.0.0.12',
      );
      expect(
        HdcService.parseIpFromIfconfig('inet 172.16.1.5 netmask 255.255.0.0'),
        '172.16.1.5',
      );
      expect(
        HdcService.parseIpFromIfconfig('inet addr:127.0.0.1 Mask:255.0.0.0'),
        null,
      );
    });
  });

  group('Harmony Screen Rotation & Display Dimensions Tests', () {
    test('parseDisplayDimensions correctly extracts width and height for portrait and landscape', () {
      const portraitOutput = '''
Display 0:
  name: "Built-in Screen"
  Width: 1260
  Height: 2720
  rotation: 0
''';
      final portrait = HarmonyMirrorService.parseDisplayDimensions(portraitOutput);
      expect(portrait.$1, 1260);
      expect(portrait.$2, 2720);
      expect(portrait.$1! < portrait.$2!, isTrue);

      const landscapeOutput = '''
Display 0:
  name: "Built-in Screen"
  Width: 2720
  Height: 1260
  rotation: 1
''';
      final landscape = HarmonyMirrorService.parseDisplayDimensions(landscapeOutput);
      expect(landscape.$1, 2720);
      expect(landscape.$2, 1260);
      expect(landscape.$1! > landscape.$2!, isTrue);
    });
  });
}
