import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';

/// 模拟多用户设备与权限变更回读，不连接真实 ADB。
class PermissionAdbFake extends AdbService {
  PermissionAdbFake() : super(executable: 'adb');
  final calls = <List<String>>[];
  bool cameraGranted = true;
  bool micGranted = true;
  bool failMic = false;
  bool ignoreRevoke = false;
  bool failUser = false;
  bool failRead = false;
  bool failMetadata = false;

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    calls.add(List.of(args));
    if (args.first == 'am') {
      return AdbResult(
        exitCode: failUser ? 1 : 0,
        stdout: failUser ? '' : '10',
        stderr: failUser ? 'user unavailable' : '',
      );
    }
    if (args.first == 'dumpsys') {
      if (failRead) throw Exception('device offline');
      return AdbResult(exitCode: 0, stdout: dump, stderr: '');
    }
    if (args[1] == 'list') {
      return AdbResult(
        exitCode: failMetadata ? 1 : 0,
        stdout: metadata,
        stderr: '',
      );
    }
    if (args[1] == 'revoke' || args[1] == 'grant') {
      if (args.last == 'android.permission.RECORD_AUDIO' && failMic) {
        return const AdbResult(exitCode: 1, stdout: '', stderr: 'policy fixed');
      }
      if (!ignoreRevoke) {
        if (args.last == 'android.permission.CAMERA') {
          cameraGranted = args[1] == 'grant';
        }
        if (args.last == 'android.permission.RECORD_AUDIO') {
          micGranted = args[1] == 'grant';
        }
      }
    }
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }

  String get dump =>
      '''
Packages:
  Package [com.example.app] (abcd):
    requested permissions:
      android.permission.CAMERA
      android.permission.RECORD_AUDIO
      android.permission.INTERNET
      vendor.permission.NEW_SENSOR
      missing.permission.UNKNOWN
    install permissions:
      android.permission.INTERNET: granted=true
    User 0: installed=true
      runtime permissions:
        android.permission.CAMERA: granted=false, flags=[ ]
    User 10: installed=true
      runtime permissions:
        android.permission.CAMERA: granted=$cameraGranted, flags=[ USER_SET ]
        android.permission.RECORD_AUDIO: granted=$micGranted, flags=[ ${failMic ? 'POLICY_FIXED' : ''} ]
      enabledComponents:
        ignored.component: granted=true
''';

  static const metadata = '''
All Permissions:
+ permission:android.permission.INTERNET
  protectionLevel:normal
+ permission:vendor.permission.NEW_SENSOR
  protectionLevel:dangerous|instant
''';
}
