import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/harmony/harmony_mirror_service.dart';

class _MockHdcService extends HdcService {
  _MockHdcService() : super(executable: 'hdc');

  final List<String> executedCommands = [];

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    executedCommands.add(command);
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

Uint8List _makeTouchEvent({
  required int action,
  required int pointerId,
  required int x,
  required int y,
  required int screenWidth,
  required int screenHeight,
}) {
  final buffer = ByteData(32);
  buffer.setUint8(0, 2); // type = 2 (touch)
  buffer.setUint8(1, action);
  buffer.setUint64(2, pointerId, Endian.big);
  buffer.setUint32(10, x, Endian.big);
  buffer.setUint32(14, y, Endian.big);
  buffer.setUint16(18, screenWidth, Endian.big);
  buffer.setUint16(20, screenHeight, Endian.big);
  buffer.setUint16(22, 65535, Endian.big);
  buffer.setUint32(24, 0, Endian.big);
  buffer.setUint32(28, 0, Endian.big);
  return buffer.buffer.asUint8List();
}

void main() {
  group('HarmonyMirrorService Touch Fallback Tests', () {
    late _MockHdcService mockHdc;
    late HarmonyMirrorService service;

    setUp(() {
      mockHdc = _MockHdcService();
      service = HarmonyMirrorService(mockHdc);
    });

    test('sendControl falls back to uinput touch-down when session is inactive', () async {
      final touchDown = _makeTouchEvent(
        action: 0,
        pointerId: 0,
        x: 540,
        y: 1100,
        screenWidth: 1080,
        screenHeight: 2400,
      );

      final result = await service.sendControl(
        deviceId: 'GHN6R19A31000851',
        controlMessage: touchDown,
      );

      expect(result, isTrue);
      expect(mockHdc.executedCommands, contains('uinput -T -d 540 1100'));
    });

    test('sendControl falls back to uinput touch-up and touch-move', () async {
      final touchMove = _makeTouchEvent(
        action: 2,
        pointerId: 0,
        x: 600,
        y: 1200,
        screenWidth: 1080,
        screenHeight: 2400,
      );
      final touchUp = _makeTouchEvent(
        action: 1,
        pointerId: 0,
        x: 600,
        y: 1200,
        screenWidth: 1080,
        screenHeight: 2400,
      );

      await service.sendControl(
        deviceId: 'GHN6R19A31000851',
        controlMessage: touchMove,
      );
      await service.sendControl(
        deviceId: 'GHN6R19A31000851',
        controlMessage: touchUp,
      );

      expect(mockHdc.executedCommands, contains('uinput -T -m 600 1200'));
      expect(mockHdc.executedCommands, contains('uinput -T -u 600 1200'));
    });

    test('sendControl returns false gracefully for unknown message types', () async {
      final invalidMessage = Uint8List.fromList([99, 0, 0, 0]);
      final result = await service.sendControl(
        deviceId: 'GHN6R19A31000851',
        controlMessage: invalidMessage,
      );

      expect(result, isFalse);
      expect(mockHdc.executedCommands, isEmpty);
    });
  });
}
