import 'dart:convert';

import '../adb/adb_service.dart';
import 'android_app_launcher.dart';

/// 应用包所在的 Android 用户空间，包含设备提供的名称和类型。
typedef AndroidAppInstance = ({int userId, String userName, String? userType});

/// 按需查找指定包的安装实例，并在选定的 Android 用户下启动应用。
class AndroidAppInstanceService {
  const AndroidAppInstanceService(this._adb);

  final AdbService _adb;
  static final _verboseUserPattern = RegExp(
    r'^\s*\d+:\s+id=(\d+), name=(.*), type=([\w.]+), flags=',
  );
  static final _legacyUserPattern = RegExp(
    r'^\s*UserInfo\{(\d+):(.*):[0-9a-fA-F]+\}(?:\s.*)?$',
  );

  /// 逐个查询用户的安装状态，保留查询受限的用户 ID 以标记结果不完整。
  Future<({List<AndroidAppInstance> instances, List<int> unavailableUserIds})>
  listInstances(String deviceId, String packageName) async {
    final users = await _listUsers(deviceId);
    final instances = <AndroidAppInstance>[];
    final unavailableUserIds = <int>[];
    for (final user in users) {
      final result = await _adb.shellArgs(deviceId, [
        'pm',
        'list',
        'packages',
        '--user',
        user.userId.toString(),
        packageName,
      ]);
      if (!result.isSuccess) {
        unavailableUserIds.add(user.userId);
      } else if (const LineSplitter()
          .convert(result.stdout)
          .any((line) => line.trim() == 'package:$packageName')) {
        instances.add(user);
      }
    }
    if (unavailableUserIds.length == users.length) {
      throw StateError('无法查询任何 Android 用户的应用安装状态');
    }
    return (instances: instances, unavailableUserIds: unavailableUserIds);
  }

  Future<List<AndroidAppInstance>> _listUsers(String deviceId) async {
    // 支持详细用户类型的设备可区分克隆、工作与普通用户，旧设备保留真实名称。
    final verbose = await _adb.shellArgs(deviceId, [
      'cmd',
      'user',
      'list',
      '-v',
    ]);
    if (verbose.isSuccess) {
      final users = _parseUsers(verbose.stdout, _verboseUserPattern);
      if (users.isNotEmpty) return users;
    }

    final legacy = await _adb.shellArgs(deviceId, ['pm', 'list', 'users']);
    if (!legacy.isSuccess) {
      throw StateError('查询 Android 用户失败：${legacy.message}');
    }
    final users = _parseUsers(legacy.stdout, _legacyUserPattern);
    if (users.isEmpty) throw StateError('无法从设备输出识别 Android 用户');
    return users;
  }

  List<AndroidAppInstance> _parseUsers(String output, RegExp pattern) {
    return [
      for (final line in const LineSplitter().convert(output))
        if (pattern.firstMatch(line) case final match?)
          if (int.tryParse(match.group(1)!) case final userId?)
            (
              userId: userId,
              userName: match.group(2)!,
              userType: match.groupCount == 3 ? match.group(3) : null,
            ),
    ];
  }

  /// 在同一用户下解析并启动明确的入口，避免 Android 将 Intent 路由到其他实例。
  Future<void> launchInUser(
    String deviceId,
    String packageName,
    int userId,
  ) async {
    final component = await resolveAppLauncherComponent(
      _adb,
      deviceId,
      packageName,
      userId: userId,
    );
    final result = await _adb.shellArgs(deviceId, [
      'am',
      'start',
      '-W',
      '--user',
      userId.toString(),
      '-a',
      'android.intent.action.MAIN',
      '-c',
      'android.intent.category.LAUNCHER',
      '-n',
      // 类名可能含有 $，保留字面量供设备端 Shell 解析。
      "'$component'",
    ]);
    final lines = const LineSplitter().convert(result.stdout);
    // 系统取消前台切换时也可能报告 Status: ok；复用已在前台的任务仍算成功。
    if (!result.isSuccess ||
        !lines.contains('Status: ok') ||
        lines.any(
          (line) => line.startsWith('Warning: Activity not started because'),
        )) {
      throw StateError('启动 Android 用户 $userId 的应用失败：${result.message}');
    }
  }
}
