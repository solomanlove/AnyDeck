import 'package:adb_manage/core/adb/adb_result.dart';
import 'package:adb_manage/core/adb/adb_service.dart';
import 'package:adb_manage/core/apps/app_permission_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAdbServiceForPermission extends AdbService {
  FakeAdbServiceForPermission() : super(executable: 'adb');

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    // 模拟 am get-current-user 或者是 dumpsys package
    final argStr = args.join(' ');
    if (argStr.contains('am get-current-user')) {
      return const AdbResult(exitCode: 0, stdout: '0\n', stderr: '');
    } else if (argStr.contains('dumpsys package')) {
      return const AdbResult(
        exitCode: 0,
        stdout: _mockDumpsysOutput,
        stderr: '',
      );
    }
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

const _mockDumpsysOutput = '''
    requested permissions:
      android.permission.WAKE_LOCK
      android.permission.INTERNET
      android.permission.CAMERA
      android.permission.ACCESS_FINE_LOCATION
    install permissions:
      android.permission.INTERNET: granted=true
      android.permission.WAKE_LOCK: granted=true
    User 0: ceDataInode=1246399 installed=true
      runtime permissions:
        android.permission.CAMERA: granted=false, flags=[ USER_SET ]
        android.permission.ACCESS_FINE_LOCATION: granted=true, flags=[ USER_SET ]
''';

void main() {
  test(
    'Parses dumpsys package output correctly to AdbAppPermission list',
    () async {
      final adbService = FakeAdbServiceForPermission();
      final permissionService = AppPermissionService(adbService);

      final permissions = await permissionService.getPermissions(
        'device_id',
        'com.example.app',
      );

      expect(permissions, hasLength(4));

      // Verify ordering is alphabetical
      expect(permissions[0].name, 'android.permission.ACCESS_FINE_LOCATION');
      expect(permissions[0].granted, isTrue);
      expect(permissions[0].isRuntime, isTrue);

      expect(permissions[1].name, 'android.permission.CAMERA');
      expect(permissions[1].granted, isFalse);
      expect(permissions[1].isRuntime, isTrue);

      expect(permissions[2].name, 'android.permission.INTERNET');
      expect(permissions[2].granted, isTrue);
      expect(permissions[2].isRuntime, isFalse);

      expect(permissions[3].name, 'android.permission.WAKE_LOCK');
      expect(permissions[3].granted, isTrue);
      expect(permissions[3].isRuntime, isFalse);
    },
  );
}
