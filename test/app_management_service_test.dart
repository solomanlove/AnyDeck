import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/apps/app_management_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAppAdbService extends AdbService {
  FakeAppAdbService() : super(executable: 'adb');

  final commands = <String>[];

  /// 模拟设备元数据，验证刷新时不会被旧缓存中的展示信息覆盖。
  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (command.startsWith('dumpsys package packages')) {
      return const AdbResult(
        exitCode: 0,
        stdout:
            '  Package [com.example.app] (123):\n'
            '    pkgFlags=[ DEBUGGABLE HAS_CODE ]\n'
            '  Package [com.android.settings] (456):\n'
            '    pkgFlags=[ SYSTEM HAS_CODE ]\n',
        stderr: '',
      );
    }
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(args.join(' '));
    final command = args.join(' ');
    if (command == 'pm list packages -f -U --user 0') {
      return const AdbResult(
        exitCode: 0,
        stdout:
            'package:/data/app/com.example/base.apk=com.example.app uid:10001\n'
            'package:/system/app/Settings/Settings.apk=com.android.settings uid:1000\n',
        stderr: '',
      );
    }
    if (command == 'pm list packages -s --user 0') {
      return const AdbResult(
        exitCode: 0,
        stdout: 'package:com.android.settings\n',
        stderr: '',
      );
    }
    if (command == 'pm list packages -f -U -d --user 0') {
      return const AdbResult(exitCode: 0, stdout: '', stderr: '');
    }
    return const AdbResult(exitCode: 1, stdout: '', stderr: 'unexpected');
  }
}

void main() {
  test('刷新恢复展示缓存后保留设备 DEBUG 状态并正确回写缓存', () async {
    SharedPreferences.setMockInitialValues({});
    final service = AppManagementService(FakeAppAdbService());
    await service.savePackageCache('device1', const [
      AdbPackage(name: 'com.example.app', label: '测试应用'),
      AdbPackage(name: 'com.android.settings', debuggable: true),
    ]);

    final packages = await service.refreshPackages(
      'device1',
      refreshIconsInBackground: false,
    );
    final debugPackage = packages.singleWhere(
      (package) => package.name == 'com.example.app',
    );
    expect(debugPackage.label, '测试应用');
    expect(debugPackage.debuggable, isTrue);
    expect(
      packages
          .singleWhere((package) => package.name == 'com.android.settings')
          .debuggable,
      isFalse,
    );

    final cached = await service.listPackages('device1');
    expect(
      cached
          .where((package) => package.debuggable)
          .map((package) => package.name),
      ['com.example.app'],
    );
  });

  test('listPackages cold path only reads fast package lists', () async {
    SharedPreferences.setMockInitialValues({});
    final adb = FakeAppAdbService();
    final service = AppManagementService(adb);

    final packages = await service.listPackages('device1');

    expect(packages.map((package) => package.name), [
      'com.android.settings',
      'com.example.app',
    ]);
    expect(packages.first.system, isTrue);
    expect(adb.commands, hasLength(3));
    expect(adb.commands.join('\n'), isNot(contains('dumpsys')));
    expect(adb.commands.join('\n'), isNot(contains('find /data/app')));
  });
}
