import 'dart:typed_data';
import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';

class FakeAdbService extends AdbService {
  FakeAdbService() : super(executable: 'adb');

  @override
  Future<List<AdbDevice>> listDevices() async {
    return [];
  }

  @override
  Stream<List<AdbDevice>> trackDevices({
    Duration interval = const Duration(seconds: 2),
  }) {
    return Stream.value([]);
  }

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final command = args.join(' ');
    if (command == 'getprop ro.serialno' ||
        command == 'getprop ro.boot.serialno') {
      return AdbResult(exitCode: 0, stdout: deviceId, stderr: '');
    }
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<Uint8List> captureScreenshot(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    return Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x01, 0x90, // 400 width
      0x00, 0x00, 0x03, 0x20, // 800 height
      0x08, 0x06, 0x00, 0x00, 0x00,
      0x1F, 0x15, 0xC4, 0x89,
      0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54,
      0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05,
      0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00,
      0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
      0x60, 0x82,
    ]);
  }
}
