import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../../app/settings/app_settings_controller.dart';

class ScreenRecordState {
  const ScreenRecordState({
    required this.isRecording,
    required this.durationSeconds,
    this.isStopping = false,
  });

  final bool isRecording;
  final int durationSeconds;
  final bool isStopping;

  ScreenRecordState copyWith({
    bool? isRecording,
    int? durationSeconds,
    bool? isStopping,
  }) {
    return ScreenRecordState(
      isRecording: isRecording ?? this.isRecording,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isStopping: isStopping ?? this.isStopping,
    );
  }
}

class ScreenRecordNotifier extends Notifier<ScreenRecordState> {
  ScreenRecordNotifier(this.deviceId);

  final String deviceId;
  Timer? _timer;
  Process? _process;
  bool _isHostRecording = false;
  String? _localRecordPath;

  @override
  ScreenRecordState build() {
    ref.onDispose(() {
      _timer?.cancel();
      if (_process != null) {
        if (!_isHostRecording) {
          ref.read(adbServiceProvider).stopScreenRecord(deviceId);
        }
        _process?.kill();
      }
    });
    return const ScreenRecordState(isRecording: false, durationSeconds: 0);
  }

  Future<void> start() async {
    if (state.isRecording) return;

    try {
      final settings = ref.read(appSettingsProvider);
      // 0. Check if device supports screenrecord
      final isSupported = await ref
          .read(adbServiceProvider)
          .isScreenRecordSupported(deviceId);
      
      _isHostRecording = settings.forceHostRecording || !isSupported;

      if (_isHostRecording) {
        final hostPlatform = ref.read(hostPlatformServiceProvider);
        _localRecordPath = hostPlatform.generateRecordPath(
          settings.screenshotSavePath,
          deviceId,
        );
        final file = File(_localRecordPath!);
        await file.parent.create(recursive: true);

        _process = await ref.read(scrcpyServiceProvider).startRecording(
          deviceId: deviceId,
          localSavePath: _localRecordPath!,
        );
      } else {
        // 1. Delete old recording file on device if it exists
        try {
          await ref
              .read(fileManagerServiceProvider)
              .delete(deviceId, '/sdcard/adb_screenrecord_temp.mp4');
        } catch (_) {}

        // 2. Start recording
        _process = await ref
            .read(adbServiceProvider)
            .startScreenRecord(deviceId, '/sdcard/adb_screenrecord_temp.mp4');
      }

      final errorBuffer = StringBuffer();
      _process!.stderr.transform(utf8.decoder).listen((data) {
        errorBuffer.write(data);
      });

      bool exitedEarly = false;
      int? exitCode;

      _process!.exitCode.then((code) {
        exitedEarly = true;
        exitCode = code;
        if (state.isRecording && !state.isStopping) {
          _timer?.cancel();
          _process = null;
          state = const ScreenRecordState(
            isRecording: false,
            durationSeconds: 0,
          );
        }
      });

      // Wait a short time to verify it didn't crash immediately
      await Future.delayed(const Duration(milliseconds: 600));
      if (exitedEarly) {
        _process = null;
        final err = errorBuffer.toString().trim();
        throw Exception(
          err.isNotEmpty ? err : 'Process exited with code $exitCode',
        );
      }

      state = const ScreenRecordState(isRecording: true, durationSeconds: 0);

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        state = state.copyWith(durationSeconds: state.durationSeconds + 1);
        if (state.durationSeconds >= 180) {
          // 3 min limit
          stop(); // Force stop
        }
      });
    } catch (e) {
      _process?.kill();
      _process = null;
      state = const ScreenRecordState(isRecording: false, durationSeconds: 0);
      rethrow;
    }
  }

  Future<String?> stop() async {
    if (!state.isRecording || state.isStopping) return null;

    state = state.copyWith(isStopping: true);
    _timer?.cancel();
    _timer = null;

    try {
      if (_isHostRecording) {
        if (_process != null) {
          _process?.kill();
          await _process!.exitCode;
        }
        _process = null;
        return 'local:$_localRecordPath';
      } else {
        // 1. Send stop command (SIGINT)
        await ref.read(adbServiceProvider).stopScreenRecord(deviceId);

        // 2. Wait for process exit
        if (_process != null) {
          await _process!.exitCode.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              _process?.kill();
              return 0;
            },
          );
        }
        _process = null;
        return '/sdcard/adb_screenrecord_temp.mp4';
      }
    } catch (e) {
      _process?.kill();
      _process = null;
      rethrow;
    } finally {
      state = const ScreenRecordState(
        isRecording: false,
        durationSeconds: 0,
        isStopping: false,
      );
    }
  }
}

final screenRecordProvider =
    NotifierProvider.family<ScreenRecordNotifier, ScreenRecordState, String>(
      ScreenRecordNotifier.new,
    );
