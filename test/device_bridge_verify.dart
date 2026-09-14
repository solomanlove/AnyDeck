import 'dart:io';

import 'package:any_deck/core/scrcpy/rust_device_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('real device verification', () async {
    final adb = '/Users/shijie/Library/Android/sdk/platform-tools/adb';
    final deviceId = '5002ba00';
    final jar = '/var/folders/s7/z2lj9cw103qbd5_67pd905br0000gn/T/any_deck_scrcpy/scrcpy-server.jar';

    expect(File(jar).existsSync(), isTrue);

    final bridge = RustDeviceBridge.instance;

    print('\n--- Testing Camera (kind 0) ---');
    final camHandle = bridge.start(adb, deviceId, jar, 0);
    print('Camera handle: $camHandle');
    expect(camHandle, greaterThan(0));

    int camStatus = 0;
    int camW = 0;
    int camH = 0;
    for (int i = 0; i < 40; i++) {
      camStatus = bridge.status(camHandle);
      final size = bridge.videoSize(camHandle);
      camW = size >> 32;
      camH = size & 0xffffffff;
      print('[$i] Camera status: $camStatus, size: ${camW}x$camH');
      if (camStatus == 1 && camW > 0 && camH > 0) break;
      if (camStatus >= 2) break;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    bridge.stop(camHandle);
    await Future.delayed(const Duration(milliseconds: 500));
    bridge.release(camHandle);

    print('\n--- Testing Microphone (kind 1) ---');
    final micHandle = bridge.start(adb, deviceId, jar, 1);
    print('Microphone handle: $micHandle');
    expect(micHandle, greaterThan(0));

    int micStatus = 0;
    for (int i = 0; i < 30; i++) {
      micStatus = bridge.status(micHandle);
      print('[$i] Mic status: $micStatus');
      if (micStatus == 1) break;
      if (micStatus >= 2) break;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    bridge.stop(micHandle);
    await Future.delayed(const Duration(milliseconds: 500));
    bridge.release(micHandle);

    print('\n--- Testing Clipboard (kind 2) ---');
    final clipHandle = bridge.start(adb, deviceId, jar, 2);
    print('Clipboard handle: $clipHandle');
    expect(clipHandle, greaterThan(0));

    int clipStatus = 0;
    for (int i = 0; i < 30; i++) {
      clipStatus = bridge.status(clipHandle);
      final rev = bridge.revision(clipHandle);
      final text = bridge.clipboard(clipHandle);
      print('[$i] Clipboard status: $clipStatus, rev: $rev, text: "$text"');
      if (clipStatus == 1) break;
      if (clipStatus >= 2) break;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    bridge.stop(clipHandle);
    await Future.delayed(const Duration(milliseconds: 500));
    bridge.release(clipHandle);

    print('FINAL RESULT: camStatus=$camStatus (${camW}x$camH), micStatus=$micStatus, clipStatus=$clipStatus');
  }, timeout: const Timeout(Duration(seconds: 45)));
}
