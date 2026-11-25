import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:any_deck/core/mcp/mcp_server.dart';
import 'package:any_deck/core/mcp/models/mcp_request.dart';
import 'package:any_deck/core/mcp/registry/mcp_registry_factory.dart';
import 'package:flutter_test/flutter_test.dart';

const _package = 'com.example.app';
const _cloneId = 42;

/// 通过实际 MCP 注册和分发执行，用假设备检查每条 ADB 命令的作用域。
void main() {
  late _Adb adb;
  late _Hdc hdc;
  late McpServer server;

  setUp(() {
    adb = _Adb();
    hdc = _Hdc();
    server = McpServer(
      registry: McpRegistryFactory(
        adb: adb,
        hdc: hdc,
        iosDevices: _IosDevices(),
        iosCommands: IosCommandService(),
      ).create(),
    );
  });

  Future<Map<String, dynamic>> request(
    String method, {
    String platform = 'android',
    Map<String, dynamic> params = const {},
  }) async {
    final response = await server.handleRequest(
      McpRequest(id: 1, method: method, params: params),
      platform: platform,
      version: '2025-11-25',
    );
    expect(response!.error, isNull);
    return response.result;
  }

  Future<Map<String, dynamic>> call(
    String name, {
    String platform = 'android',
    Map<String, dynamic> args = const {},
  }) => request(
    'tools/call',
    platform: platform,
    params: {
      'name': name,
      'arguments': {
        'deviceId': platform == 'android' ? 'a' : 'h',
        'packageName': _package,
        ...args,
      },
    },
  );

  test('Android 公开只读实例查询和双开指引', () async {
    final android = await request('tools/list');
    final tools = (android['tools'] as List).cast<Map<String, dynamic>>();
    final listTool = tools.singleWhere(
      (tool) => tool['name'] == 'list_app_instances',
    );
    expect(listTool['annotations']['readOnlyHint'], isTrue);

    for (final platform in ['android', 'harmony', 'ios', 'all']) {
      final result = await request(
        'initialize',
        platform: platform,
        params: const {'protocolVersion': '2025-11-25'},
      );
      expect(
        result['instructions'],
        platform == 'android' || platform == 'all'
            ? contains('list_app_instances')
            : isNot(contains('list_app_instances')),
      );
    }
    for (final platform in ['harmony', 'ios']) {
      final result = await request('tools/list', platform: platform);
      expect(
        (result['tools'] as List).map((tool) => tool['name']),
        isNot(contains('list_app_instances')),
      );
    }
  });

  test('查询精确匹配包名，使用发现的用户 ID 解析和启动同一实例', () async {
    final list = await call('list_app_instances');
    expect(list['isError'], isFalse);
    final data = list['structuredContent'];
    expect(data['instances'], [
      {'userId': 0, 'userName': 'Owner', 'userType': 'full.SYSTEM'},
      {'userId': _cloneId, 'userName': '双开, 空间', 'userType': 'profile.CLONE'},
    ]);
    expect(data['unavailableUserIds'], isEmpty);
    final selected = (data['instances'] as List).last['userId'];
    final launch = await call('launch_app', args: {'userId': selected});
    expect(launch['isError'], isFalse);
    expect(launch['structuredContent']['userId'], _cloneId);
    expect(adb.commands[adb.commands.length - 2], [
      'cmd',
      'package',
      'resolve-activity',
      '--brief',
      '--user',
      '42',
      '-a',
      'android.intent.action.MAIN',
      '-c',
      'android.intent.category.LAUNCHER',
      '-p',
      _package,
    ]);
    expect(adb.commands.last, [
      'am',
      'start',
      '-W',
      '--user',
      '42',
      '-a',
      'android.intent.action.MAIN',
      '-c',
      'android.intent.category.LAUNCHER',
      '-n',
      "'$_package/.Main\$Alias'",
    ]);
  });

  test('旧系统回退到用户清单，查询受限的用户保留为未知', () async {
    adb.legacyUsers = true;
    adb.blockedUsers = {0};
    final list = await call('list_app_instances');
    expect(list['isError'], isFalse);
    expect(adb.commands[1], ['pm', 'list', 'users']);
    expect(list['structuredContent']['instances'], [
      {'userId': _cloneId, 'userName': 'XSpace: 双开'},
    ]);
    expect(list['structuredContent']['unavailableUserIds'], [0]);
  });

  test('全部用户的查询都失败时返回工具错误', () async {
    adb.blockedUsers = {0, _cloneId, 50};
    final list = await call('list_app_instances');
    expect(list['isError'], isTrue);
  });

  test('默认 Android 和 HarmonyOS 启动方式保持兼容', () async {
    final android = await call('launch_app');
    expect(android['isError'], isFalse);
    expect(android['structuredContent'], isNot(contains('userId')));
    expect(adb.commands.single, ['monkey', '-p', _package, '1']);

    final harmony = await call('launch_app', platform: 'harmony');
    expect(harmony['isError'], isFalse);
    expect(hdc.commands.single, 'aa start -b $_package -a EntryAbility');
  });

  test('非法用户、包名及 HarmonyOS 用户参数均在调用 ADB 前被拒绝', () async {
    for (final userId in [-1, 2147483648, '42', 4.2]) {
      final result = await call('launch_app', args: {'userId': userId});
      expect(result['isError'], isTrue);
    }
    for (final name in ['list_app_instances', 'launch_app']) {
      final result = await call(name, args: {'packageName': '$_package; id'});
      expect(result['isError'], isTrue);
    }
    final harmony = await call(
      'launch_app',
      platform: 'harmony',
      args: {'userId': _cloneId},
    );
    expect(harmony['isError'], isTrue);
    expect(hdc.commands, isEmpty);
    expect(adb.commands, isEmpty);
  });

  test('无法解析指定用户的入口时停止，绝不启动默认实例', () async {
    final launch = await call('launch_app', args: {'userId': 999});
    expect(launch['isError'], isTrue);
    expect(adb.commands.single[2], 'resolve-activity');
  });

  test('Activity Manager 返回超时时，退出码为零也报告工具错误', () async {
    adb.startOutput = 'Status: timeout\n';
    final launch = await call('launch_app', args: {'userId': _cloneId});
    expect(launch['isError'], isTrue);
  });

  test('区分系统保留当前界面与双开任务已在前台', () async {
    adb.startOutput =
        'Warning: Activity not started because the current '
        'activity is being kept for the user.\nStatus: ok\n';
    final blocked = await call('launch_app', args: {'userId': _cloneId});
    expect(blocked['isError'], isTrue);

    adb.startOutput =
        'Warning: Activity not started, intent has been '
        'delivered to currently running top-most instance.\nStatus: ok\n';
    final reused = await call('launch_app', args: {'userId': _cloneId});
    expect(reused['isError'], isFalse);
  });
}

class _Adb extends AdbService {
  final commands = <List<String>>[];
  bool legacyUsers = false;
  Set<int> blockedUsers = {};
  String startOutput = 'Status: ok\n';

  @override
  Future<List<DiscoveredDevice>> listDevices() async => const [
    DiscoveredDevice(id: 'a', status: 'device'),
  ];

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    expect(deviceId, 'a');
    commands.add(args);
    final userArg = args.indexOf('--user');
    final userId = userArg < 0 ? null : int.parse(args[userArg + 1]);
    final output = switch (args) {
      ['cmd', 'user', 'list', '-v'] when legacyUsers => 'Unknown option: -v',
      ['cmd', 'user', 'list', '-v'] =>
        '3 users:\n0: id=0, name=Owner, type=full.SYSTEM, flags=SYSTEM\n'
            '1: id=42, name=双开, 空间, type=profile.CLONE, flags=PROFILE\n'
            '2: id=50, name=Guest, type=full.GUEST, flags=FULL',
      ['pm', 'list', 'users'] =>
        'Users:\n\tUserInfo{0:Owner:4c13} running\n'
            '\tUserInfo{42:XSpace: 双开:801010} running\n',
      ['pm', 'list', 'packages', ...] when blockedUsers.contains(userId) => '',
      ['pm', 'list', 'packages', ...] when userId == 50 =>
        'package:$_package.other\n',
      ['pm', 'list', 'packages', ...] => 'package:$_package\n',
      ['cmd', 'package', 'resolve-activity', ...] when userId == _cloneId =>
        'priority=0\n$_package/.Main\$Alias\n',
      ['cmd', 'package', 'resolve-activity', ...] => 'No activity found\n',
      ['am', 'start', ...] => startOutput,
      ['monkey', '-p', _package, '1'] => 'Events injected: 1',
      _ => throw StateError('预期之外的 ADB 命令 $args'),
    };
    return AdbResult(
      exitCode: blockedUsers.contains(userId) ? 1 : 0,
      stdout: output,
      stderr: '',
    );
  }
}

class _Hdc extends HdcService {
  final commands = <String>[];

  @override
  Future<List<DiscoveredDevice>> listDevices() async => const [
    DiscoveredDevice(id: 'h', status: 'device', isHarmony: true),
  ];

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(command);
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

class _IosDevices extends IosDeviceService {
  @override
  Future<List<DiscoveredDevice>> listDevices() async => [];
}
