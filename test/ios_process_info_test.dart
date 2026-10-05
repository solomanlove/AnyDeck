import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/ios/ios_app_info.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_process_info.dart';
import 'package:any_deck/core/ios/ios_process_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const _processJson = '''
{"level":"WARN","msg":"agent is not running"}
[{"IsApplication":true,"Name":"NotificationService","Pid":286,"RealAppName":"/private/var/containers/Bundle/Application/A/Netdisk.app/PlugIns/NotificationService.appex/NotificationService","StartDate":"2026-10-05T22:36:49.817+08:00"}]
''';
const _appsJson = '''
[{"CFBundleIdentifier":"com.example.disk","CFBundleDisplayName":"网盘","CFBundleShortVersionString":"13.32.2","ApplicationType":"User","Path":"/var/containers/Bundle/Application/A/Netdisk.app"}]
''';

/// 服务级命令桩：验证设备路由、一次应用查询及失败降级。
class _Commands extends IosCommandService {
  final calls = <List<String>>[];
  bool appsFail = false;
  bool processesFail = false;
  String processes = _processJson;

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    calls.add(args);
    final apps = args.first == 'apps';
    return AdbResult(
      exitCode: (apps ? appsFail : processesFail) ? 1 : 0,
      stdout: apps ? _appsJson : processes,
      stderr: '',
    );
  }
}

void main() {
  test('读取真机结构的 Name、RealAppName、StartDate、IsApplication', () {
    final process = IosCommandService.parseProcesses(_processJson).single;
    expect(process.pid, 286);
    expect(process.name, 'NotificationService');
    expect(process.isApplication, isTrue);
    expect(process.isExtension, isTrue);
    expect(process.startedAt, DateTime.utc(2026, 10, 5, 14, 36, 49, 817));
    expect(process.bundleId, isNull);
  });

  test('关联扩展宿主，并保留应用路径供图标 copyWith 使用', () {
    final apps = IosCommandService.parseApps(_appsJson);
    final app = apps.single.copyWith(iconPath: '/tmp/icon.png');
    expect(app.path, apps.single.path);
    final process = IosProcessParser.associate(
      IosCommandService.parseProcesses(_processJson),
      [app],
    ).single;
    expect(process.displayName, '网盘 · NotificationService');
    expect(process.app?.bundleId, 'com.example.disk');
    expect(process.app?.version, '13.32.2');
    expect(process.bundleId, isNull); // 宿主 ID 不能覆盖扩展自身的 ID。
  });

  test('同名 Runner 必须按完整安装路径匹配，不猜测无路径进程', () {
    const apps = [
      IosAppInfo(
        bundleId: 'com.example.a',
        name: 'A',
        path: '/var/apps/A/Runner.app',
      ),
      IosAppInfo(
        bundleId: 'com.example.b',
        name: 'B',
        path: '/private/var/apps/B/Runner.app/',
      ),
    ];
    final processes = IosProcessParser.associate(const [
      IosProcessInfo(
        pid: 1,
        name: 'Runner',
        executablePath: '/private/var/apps/A/Runner.app/Runner',
      ),
      IosProcessInfo(
        pid: 2,
        name: 'Runner',
        executablePath: '/var/apps/B/Runner.app/Runner',
      ),
      IosProcessInfo(pid: 3, name: 'Runner'),
      IosProcessInfo(
        pid: 4,
        name: 'Runner',
        executablePath: '/var/apps/C/Runner.app/Runner',
      ),
      IosProcessInfo(
        pid: 5,
        name: 'Runner',
        executablePath: '/var/apps/A/Runner.app.other/Runner',
      ),
    ], apps);
    expect(processes.map((item) => item.app?.bundleId), [
      'com.example.a',
      'com.example.b',
      null,
      null,
      null,
    ]);
  });

  test('重复安装路径不猜归属，主进程可以按明确 Bundle ID 关联', () {
    const apps = [
      IosAppInfo(
        bundleId: 'com.example.a',
        name: 'A',
        path: '/Applications/A.app',
      ),
      IosAppInfo(
        bundleId: 'com.example.b',
        name: 'B',
        path: '/Applications/A.app',
      ),
    ];
    final result = IosProcessParser.associate(const [
      IosProcessInfo(
        pid: 1,
        name: 'A',
        executablePath: '/Applications/A.app/A',
      ),
      IosProcessInfo(pid: 2, name: 'B', bundleId: 'com.example.b'),
    ], apps);
    expect(result.first.app, isNull);
    expect(result.last.app?.name, 'B');
  });

  test('兼容旧字段和 PID 映射，过滤日志及无效日期，不遍历进程内部元数据', () {
    const output = '''
{"level":"ERROR","Pid":7,"Name":"not a process"}
{"count":99,"processes":[{"pid":10,"name":"Demo","StartDate":"invalid","metadata":{"Pid":20,"Name":"nested"}},{"ProcessIdentifier":"11","ExecutableName":"Other"}]}
{"12":{"Name":"Mapped"}}
{"MapName":13}
{"Pid":0,"Name":"invalid"}
''';
    final result = IosCommandService.parseProcesses(output);
    expect(result.map((item) => item.pid), unorderedEquals([10, 11, 12, 13]));
    expect(result.singleWhere((item) => item.pid == 10).startedAt, isNull);
    expect(result.singleWhere((item) => item.pid == 12).name, 'Mapped');
  });

  test('每次刷新只查询一次同设备的应用列表，应用查询失败仍返回进程', () async {
    final commands = _Commands();
    final first = await commands.listProcesses('device-a');
    expect(first.single.app?.bundleId, 'com.example.disk');
    expect(commands.calls, [
      ['ps', '--apps', '--udid=device-a'],
      ['apps', '--all', '--udid=device-a'],
    ]);
    commands.appsFail = true;
    final second = await commands.listProcesses('device-b');
    expect(second.single.name, 'NotificationService');
    expect(second.single.app, isNull);
    expect(commands.calls.last.last, '--udid=device-b');
  });

  test('进程查询失败或空列表不额外查询应用', () async {
    final commands = _Commands()..processesFail = true;
    await expectLater(commands.listProcesses('device-a'), throwsException);
    expect(commands.calls, hasLength(1));
    commands.processesFail = false;
    commands.processes = '[]';
    expect(await commands.listProcesses('device-a'), isEmpty);
    expect(commands.calls, hasLength(2));
  });

  // 只在显式传入 UDID 时执行真实只读查询，不结束任何进程。
  const udid = String.fromEnvironment('IOS_PROCESS_UDID');
  if (udid.isNotEmpty) {
    test('真机进程可读取名称并关联应用 Bundle ID', () async {
      final processes = await IosCommandService().listProcesses(udid);
      expect(processes, isNotEmpty);
      expect(processes.any((item) => item.app != null), isTrue);
      expect(processes.every((item) => !item.name.startsWith('PID ')), isTrue);
    });
  }
}
