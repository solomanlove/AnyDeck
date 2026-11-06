import 'dart:async';

import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/adb/device_discovery_tracker.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _SlowIosDevices extends IosDeviceService {
  final pending = Completer<List<DiscoveredDevice>>();
  int calls = 0;

  @override
  Future<List<DiscoveredDevice>> listDevices() {
    calls++;
    return pending.future;
  }
}

void main() {
  test('iOS 设备发现慢请求不会重入', () async {
    final ios = _SlowIosDevices();
    final tracker = DeviceDiscoveryTracker(
      adbService: AdbService(executable: 'adb'),
      iosDeviceService: ios,
      isSubWindow: true,
    );
    addTearDown(tracker.dispose);

    final first = tracker.refreshIosDevices();
    final second = tracker.refreshIosDevices();
    expect(ios.calls, 1);
    ios.pending.complete(const []);
    await Future.wait([first, second]);
  });
}
