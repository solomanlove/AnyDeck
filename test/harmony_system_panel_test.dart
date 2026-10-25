import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _PanelHdcService extends HdcService {
  _PanelHdcService(this.displayOutput) : super(executable: 'hdc');

  final String displayOutput;
  final List<String> commands = [];

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(command);
    return AdbResult(
      exitCode: 0,
      stdout: command.startsWith('hidumper') ? displayOutput : '',
      stderr: '',
    );
  }
}

void main() {
  test('鸿蒙通知中心与控制中心使用屏幕两侧的安全坐标', () async {
    final hdc = _PanelHdcService('Width: 1224\nHeight: 2776\n');

    expect((await hdc.openSystemPanel('phone', quickSettings: false)).isSuccess, isTrue);
    expect(hdc.commands.last, 'uinput -T -m 122 56 122 972 300');

    expect((await hdc.openSystemPanel('phone', quickSettings: true)).isSuccess, isTrue);
    expect(hdc.commands.last, 'uinput -T -m 1102 56 1102 972 300');
  });

  test('屏幕尺寸不可用时不执行盲目触摸', () async {
    final hdc = _PanelHdcService('permission denied');

    expect((await hdc.openSystemPanel('phone', quickSettings: true)).isSuccess, isFalse);
    expect(hdc.commands, hasLength(1));
  });
}
