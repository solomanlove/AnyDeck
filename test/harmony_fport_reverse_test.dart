import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/network/port_forward_command.dart';
import 'package:any_deck/core/providers/network_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('filterReverseOnly', () {
    test('从 fport ls 输出中只保留 [Reverse] 条目并去掉标注', () {
      const raw = '''
192.168.31.83:5555    tcp:1234 localabstract:webview_devtools_remote_1234    [Forward]
192.168.31.83:5555    tcp:8788 tcp:8788    [Reverse]
192.168.31.83:5555    tcp:8081 tcp:8080    [Reverse]
''';
      final filtered = HdcServiceFport.filterReverseOnly(raw);
      expect(filtered, 'tcp:8788 tcp:8788\ntcp:8081 tcp:8080');
    });

    test('只有正向转发时返回空字符串', () {
      const raw = '''
192.168.31.83:5555    tcp:1234 localabstract:xxx    [Forward]
''';
      expect(HdcServiceFport.filterReverseOnly(raw), isEmpty);
    });

    test('无任何转发时返回空字符串', () {
      expect(HdcServiceFport.filterReverseOnly(''), isEmpty);
    });
  });

  group('parseReverseList', () {
    test('解析鸿蒙过滤后的反向转发 stdout', () {
      final list = parseReverseList('tcp:8788 tcp:8788\ntcp:8081 tcp:8080');
      expect(list.length, 2);
      expect(list[0].devicePort, 'tcp:8788');
      expect(list[0].localPort, 'tcp:8788');
      expect(list[1].devicePort, 'tcp:8081');
      expect(list[1].localPort, 'tcp:8080');
    });

    test('兼容安卓 adb reverse --list 格式', () {
      final list = parseReverseList('ABC123 tcp:8081 tcp:8080');
      expect(list.length, 1);
      expect(list[0].devicePort, 'tcp:8081');
      expect(list[0].localPort, 'tcp:8080');
    });

    test('forward 的 localabstract 行不会被误解析', () {
      final list = parseReverseList(
        '192.168.31.83:5555 tcp:1234 localabstract:webview_devtools_remote',
      );
      expect(list, isEmpty);
    });
  });

  group('parseForwardList', () {
    test('ADB 正向规则按本地端口到设备端口解析', () {
      final list = parseForwardList('ABC123 tcp:9100 tcp:8080');
      expect(list, hasLength(1));
      expect(list.single.localPort, 'tcp:9100');
      expect(list.single.devicePort, 'tcp:8080');
    });

    test('HDC 正向列表排除反向规则和 Web 调试 socket', () {
      const raw = '''
192.168.31.83:5555 tcp:9100 tcp:8080 [Forward]
192.168.31.83:5555 tcp:8788 tcp:8788 [Reverse]
192.168.31.83:5555 tcp:1234 localabstract:devtools [Forward]
''';
      final list = parseForwardList(raw);
      expect(list, hasLength(1));
      expect(list.single.localPort, 'tcp:9100');
      expect(list.single.devicePort, 'tcp:8080');
    });
  });

  group('正向端口命令', () {
    test('Android 添加和删除使用 adb forward', () async {
      final adb = _RecordingAdbService();
      await PortForwardCommand.addForward(
        adb,
        null,
        deviceId: 'android-id',
        isHarmony: false,
        localPort: 9100,
        devicePort: 8080,
      );
      expect(adb.lastArgs, [
        '-s',
        'android-id',
        'forward',
        'tcp:9100',
        'tcp:8080',
      ]);

      await PortForwardCommand.removeForward(
        adb,
        null,
        deviceId: 'android-id',
        isHarmony: false,
        localPort: 9100,
        devicePort: 8080,
      );
      expect(adb.lastArgs, [
        '-s',
        'android-id',
        'forward',
        '--remove',
        'tcp:9100',
      ]);
    });

    test('Harmony 删除同时传入本地与设备节点', () async {
      final adb = _RecordingAdbService();
      final hdc = _RecordingHdcService();
      await PortForwardCommand.addForward(
        adb,
        hdc,
        deviceId: 'harmony-id',
        isHarmony: true,
        localPort: 9100,
        devicePort: 8080,
      );
      expect(hdc.lastArgs, [
        '-t',
        'harmony-id',
        'fport',
        'tcp:9100',
        'tcp:8080',
      ]);

      await PortForwardCommand.removeForward(
        adb,
        hdc,
        deviceId: 'harmony-id',
        isHarmony: true,
        localPort: 9100,
        devicePort: 8080,
      );
      expect(hdc.lastArgs, [
        '-t',
        'harmony-id',
        'fport',
        'rm',
        'tcp:9100',
        'tcp:8080',
      ]);
    });

    test('Harmony 查询只返回标记为 Forward 的规则', () async {
      final adb = _RecordingAdbService();
      final hdc = _RecordingHdcService()
        ..stdout = 'tcp:9100 tcp:8080 [Forward]\n'
            'tcp:8788 tcp:8788 [Reverse]';
      final result = await PortForwardCommand.listForward(
        adb, hdc, deviceId: 'harmony-id', isHarmony: true,
      );
      expect(hdc.lastArgs, ['-t', 'harmony-id', 'fport', 'ls']);
      expect(result.stdout, 'tcp:9100 tcp:8080 [Forward]');
    });

    test('无效端口不启动外部命令', () async {
      final adb = _RecordingAdbService();
      final result = await PortForwardCommand.addForward(
        adb,
        null,
        deviceId: 'android-id',
        isHarmony: false,
        localPort: 0,
        devicePort: 8080,
      );
      expect(result.isSuccess, isFalse);
      expect(adb.lastArgs, isNull);
    });
  });
}

class _RecordingAdbService extends AdbService {
  _RecordingAdbService() : super(executable: 'adb');

  List<String>? lastArgs;

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    lastArgs = args;
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

class _RecordingHdcService extends HdcService {
  _RecordingHdcService() : super(executable: 'hdc');

  List<String>? lastArgs;
  String stdout = '';

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    lastArgs = args;
    return AdbResult(exitCode: 0, stdout: stdout, stderr: '');
  }
}