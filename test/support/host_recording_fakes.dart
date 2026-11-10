// 电脑录制生命周期测试替身；不加载 Rust 库，不启动外部命令。
import 'dart:async';
import 'dart:io';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/host_recording_backend.dart';

class RecordingTestSettings extends AppSettingsController {
  RecordingTestSettings(this.path, this.force);
  final String path;
  final bool force;
  @override
  AppSettings build() =>
      AppSettings(forceHostRecording: force, screenshotSavePath: path);
}

class RecordingTestRegistry extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => [];
}

class RecordingTestAdb extends AdbService {
  RecordingTestAdb() : super(executable: '/not-installed/adb');
  bool supported = true;
  int displayCalls = 0;
  @override
  Future<bool> isScreenRecordSupported(String deviceId) async => supported;
  @override
  Future<Process> startDisplayScreenRecord(
    String deviceId,
    String remotePath,
    int displayId, {
    int timeLimit = 180,
  }) async {
    displayCalls++;
    throw StateError('fixture: device display recording');
  }
}

class RecordingTestHost implements HostRecordingBackend {
  final entered = Completer<void>();
  Completer<void>? starting;
  Completer<void>? stopping;
  final exit = Completer<String?>();
  int starts = 0;
  int stops = 0;
  int cancellations = 0;
  bool failStop = false;
  @override
  Future<void> start() async {
    starts++;
    entered.complete();
    await starting?.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    await stopping?.future;
    if (failStop) throw StateError('MP4 finalize failed');
  }

  @override
  void cancel() {
    cancellations++;
  }

  @override
  Future<String?> get exited => exit.future;
}
