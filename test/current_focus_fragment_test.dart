import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/device_actions/device_action_service.dart';

class StubAdbServiceForFocus extends AdbService {
  StubAdbServiceForFocus({
    required this.focusOutput,
    required this.activityOutput,
  });

  final String focusOutput;
  final String activityOutput;

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (command.contains('mCurrentFocus')) {
      return AdbResult(exitCode: 0, stdout: focusOutput, stderr: '');
    } else if (command.contains('dumpsys activity')) {
      return AdbResult(exitCode: 0, stdout: activityOutput, stderr: '');
    }
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  group('Current Focus Fragment Parsing Tests', () {
    test('Should display only focus line if no fragments found', () async {
      final adb = StubAdbServiceForFocus(
        focusOutput:
            'mCurrentFocus=Window{2baae81 u0 com.xxxx.xxxx/com.xxxx.xxxx.ui.MainActivity}\n',
        activityOutput: 'No fragments here',
      );
      final service = DeviceActionService(adb);

      final result = await service.currentFocus('device1');
      expect(result.isSuccess, isTrue);
      expect(
        result.message,
        'mCurrentFocus=Window{2baae81 u0 com.xxxx.xxxx/com.xxxx.xxxx.ui.MainActivity}',
      );
    });

    test('Should parse and display fragments when they exist', () async {
      final adb = StubAdbServiceForFocus(
        focusOutput:
            'mCurrentFocus=Window{2baae81 u0 com.xxxx.xxxx/com.xxxx.xxxx.ui.MainActivity}\n',
        activityOutput: '''
Added Fragments:
  #0: MainFragment{186a79e9 #0 id=0x7f0900cf}
  #1: ChildFragment{2c3d4e5f #1 parent=MainFragment}
  #2: ReportFragment{3e4f5a6b}
''',
      );
      final service = DeviceActionService(adb);

      final result = await service.currentFocus('device1');
      expect(result.isSuccess, isTrue);
      expect(
        result.message,
        'mCurrentFocus=Window{2baae81 u0 com.xxxx.xxxx/com.xxxx.xxxx.ui.MainActivity}\n\n'
        'Active Fragments:\n'
        '  - ChildFragment\n'
        '  - MainFragment',
      );
    });
  });
}
