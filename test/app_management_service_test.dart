import 'package:adb_manage/core/adb/adb_result.dart';
import 'package:adb_manage/core/adb/adb_service.dart';
import 'package:adb_manage/core/apps/app_management_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAppAdbService extends AdbService {
  FakeAppAdbService() : super(executable: 'adb');

  final commands = <String>[];

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
