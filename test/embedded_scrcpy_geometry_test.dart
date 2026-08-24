import 'package:any_deck/core/device_info/device_display_frame.dart';
import 'package:any_deck/features/control/embedded_scrcpy_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScrcpyVideoGeometry.resolveDisplayAwareAspectRatio', () {
    test('uses the decoded landscape frame while display state is stale', () {
      const stalePortraitDisplay = DeviceDisplayFrame(
        width: 1080,
        height: 2340,
        rotation: 0,
      );

      final aspectRatio = ScrcpyVideoGeometry.resolveDisplayAwareAspectRatio(
        videoWidth: 2340,
        videoHeight: 1080,
        displayFrame: stalePortraitDisplay,
        fallbackResolution: '1080x2340',
      );

      expect(aspectRatio, 2340 / 1080);
    });

    test('uses the decoded portrait frame while display state is stale', () {
      const staleLandscapeDisplay = DeviceDisplayFrame(
        width: 2340,
        height: 1080,
        rotation: 1,
      );

      final aspectRatio = ScrcpyVideoGeometry.resolveDisplayAwareAspectRatio(
        videoWidth: 1080,
        videoHeight: 2340,
        displayFrame: staleLandscapeDisplay,
        fallbackResolution: '2340x1080',
      );

      expect(aspectRatio, 1080 / 2340);
    });
  });
}
