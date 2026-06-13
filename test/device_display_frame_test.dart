import 'package:any_deck/core/device_info/device_display_frame.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceDisplayFrame.parseDumpsysDisplay', () {
    test('parses viewport logicalFrame list format', () {
      final frame = DeviceDisplayFrame.parseDumpsysDisplay(
        'Viewport INTERNAL: orientation=0, logicalFrame=[0, 0, 1080, 2340]',
      );

      expect(frame?.width, 1080);
      expect(frame?.height, 2340);
      expect(frame?.rotation, 0);
    });

    test('parses viewport logicalFrame Rect format', () {
      final frame = DeviceDisplayFrame.parseDumpsysDisplay(
        'Viewport INTERNAL: orientation=1, logicalFrame=Rect(0, 0 - 2340, 1080)',
      );

      expect(frame?.width, 2340);
      expect(frame?.height, 1080);
      expect(frame?.rotation, 1);
    });

    test('falls back to primary display override info', () {
      final frame = DeviceDisplayFrame.parseDumpsysDisplay(
        'DisplayDeviceInfo{"Built-in Screen": displayId 0, '
        'mOverrideDisplayInfo=DisplayInfo{"Built-in Screen", app 1080 x 2340, '
        'real 1080 x 2340, rotation 0}}',
      );

      expect(frame?.width, 1080);
      expect(frame?.height, 2340);
      expect(frame?.rotation, 0);
    });
  });
}
