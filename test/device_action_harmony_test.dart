import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/device_actions/device_action_service.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _HarmonyAdbService extends AdbService {
  _HarmonyAdbService() : super(executable: 'adb');

  final List<List<String>> shellCommands = [];

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    shellCommands.add(args);
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

class _FakeHdcService extends HdcService {
  _FakeHdcService() : super(executable: 'hdc');

  final List<(int keyCode, int repeat)> keyEvents = [];

  @override
  Future<AdbResult> injectKey(
    String deviceId,
    int keyCode, {
    int repeat = 1,
  }) async {
    keyEvents.add((keyCode, repeat));
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

class _CommandHdcService extends HdcService {
  _CommandHdcService({this.queryOutput = '', this.failUiTest = false})
    : super(executable: 'hdc');

  final String queryOutput;
  final bool failUiTest;
  final List<String> shellCommands = [];
  final List<List<String>> runCommands = [];

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    shellCommands.add(command);
    if (failUiTest && command.startsWith('uitest uiInput text')) {
      return const AdbResult(exitCode: 1, stdout: '', stderr: 'unsupported');
    }
    return AdbResult(
      exitCode: 0,
      stdout: command.startsWith('mediatool query') ? queryOutput : '',
      stderr: '',
    );
  }

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    runCommands.add(args);
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  const deviceId = 'harmony-device';

  test('HarmonyOS key events use OpenHarmony key codes', () async {
    final adb = _HarmonyAdbService();
    final hdc = _FakeHdcService();
    final service = DeviceActionService(
      adb,
      hdc: hdc,
      isHarmonyResolver: (_) => true,
    );

    await service.keyEvent(deviceId, 4);
    await service.keyEvent(deviceId, 3);
    await service.keyEvent(deviceId, 187);
    await service.volumeUp(deviceId);
    await service.volumeDown(deviceId);
    await service.standby(deviceId);

    expect(hdc.keyEvents, [
      (2, 1),
      (1, 1),
      (10011, 1),
      (16, 1),
      (17, 1),
      (18, 1),
    ]);
    expect(adb.shellCommands, isEmpty);
  });

  test('HarmonyOS volume boundaries repeat the matching key', () async {
    final hdc = _FakeHdcService();
    final service = DeviceActionService(
      _HarmonyAdbService(),
      hdc: hdc,
      isHarmonyResolver: (_) => true,
    );

    await service.volumeMax(deviceId);
    await service.volumeMute(deviceId);

    expect(hdc.keyEvents, [(16, 30), (17, 30)]);
  });

  test('unsupported Android key is not forwarded as HarmonyOS key', () async {
    final hdc = _FakeHdcService();
    final service = DeviceActionService(
      _HarmonyAdbService(),
      hdc: hdc,
      isHarmonyResolver: (_) => true,
    );

    final result = await service.keyEvent(deviceId, 999);

    expect(result.isSuccess, isFalse);
    expect(hdc.keyEvents, isEmpty);
  });

  test(
    'HDC helpers build HarmonyOS commands including Unicode text input',
    () async {
      final hdc = _CommandHdcService();

      await hdc.injectKey(deviceId, 16, repeat: 2);
      await hdc.inputText(deviceId, "It's OK");
      await hdc.inputText(deviceId, '中文');
      await hdc.setScreenPower(deviceId, powerOn: false);
      await hdc.setScreenPower(deviceId, powerOn: true);

      expect(hdc.shellCommands, [
        'uinput -K -d 16 -u 16 -d 16 -u 16',
        "uitest uiInput text 'It'\\''s OK'",
        "uitest uiInput text '中文'",
        'power-shell suspend',
        'power-shell wakeup',
      ]);
    },
  );

  test('HarmonyOS text input falls back to uinput for legacy ASCII', () async {
    final hdc = _CommandHdcService(failUiTest: true);

    final asciiResult = await hdc.inputText(deviceId, 'legacy');
    final unicodeResult = await hdc.inputText(deviceId, '中文');

    expect(asciiResult.isSuccess, isTrue);
    expect(unicodeResult.isSuccess, isFalse);
    expect(hdc.shellCommands, [
      "uitest uiInput text 'legacy'",
      "uinput -K -t 'legacy'",
      "uitest uiInput text '中文'",
    ]);
  });

  test('HarmonyOS media URI is exported before HDC receive', () async {
    final hdc = _CommandHdcService(
      queryOutput: 'uri: file://media/Photo/2/VID_001/test.mp4',
    );

    await hdc.receiveScreenRecord(deviceId, 'test.mp4', '/tmp/test.mp4');

    expect(hdc.shellCommands, [
      'mediatool query "test.mp4" -u',
      'mediatool recv "file://media/Photo/2/VID_001/test.mp4" '
          '/data/local/tmp/test.mp4',
      'rm /data/local/tmp/test.mp4',
    ]);
    expect(hdc.runCommands.single, [
      '-t',
      deviceId,
      'file',
      'recv',
      '/data/local/tmp/test.mp4',
      '/tmp/test.mp4',
    ]);
  });
}
