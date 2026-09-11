import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../core/providers/app_providers.dart';
import '../model/screenshot_state.dart';

/// 录屏执行器，专职负责录屏进程启动、时长计时、停止信号与文件拉取等五阶段生命周期管理。
class ScreenshotRecordRunner {
  ScreenshotRecordRunner({
    required this.deviceId,
    required this.ref,
    required this.onPhaseChanged,
    required this.onDurationChanged,
  });

  final String deviceId;
  final Ref ref;
  final ValueChanged<ScreenRecordPhase> onPhaseChanged;
  final ValueChanged<int> onDurationChanged;

  Process? _recordProcess;
  Timer? _recordTimer;
  int _duration = 0;
  bool _isHostRecording = false;
  bool _isHarmonyRecording = false;
  String? _localRecordPath;
  String? _harmonyRecordFileName;

  RegisteredDevice? _getDevice() {
    final list = ref.read(deviceRegistryProvider);
    try {
      return list.firstWhere((d) => d.id == deviceId);
    } catch (_) {
      return null;
    }
  }

  /// 释放录屏资源，安全清理僵尸进程与计时器
  void dispose() {
    _recordTimer?.cancel();
    if (_isHarmonyRecording) {
      unawaited(ref.read(hdcServiceProvider).stopScreenRecord(deviceId));
    } else if (_recordProcess != null) {
      if (!_isHostRecording) {
        ref.read(adbServiceProvider).stopScreenRecord(deviceId);
      }
      _recordProcess?.kill();
    }
  }

  /// 启动录屏进程 (starting -> recording)
  Future<void> startRecording({required BuildContext context}) async {
    onPhaseChanged(ScreenRecordPhase.starting);
    _duration = 0;
    onDurationChanged(0);

    try {
      final settings = ref.read(appSettingsProvider);
      final device = _getDevice();
      final isHarmony = device?.isHarmony == true;

      if (isHarmony) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        _harmonyRecordFileName = 'anydeck_record_$timestamp.mp4';
        final hostPlatform = ref.read(hostPlatformServiceProvider);
        _localRecordPath = hostPlatform.generateRecordPath(
          settings.screenshotSavePath,
          deviceId,
        );
        await File(_localRecordPath!).parent.create(recursive: true);
        final result = await ref
            .read(hdcServiceProvider)
            .startScreenRecord(deviceId, _harmonyRecordFileName!);
        if (!result.isSuccess) {
          throw Exception(result.message);
        }
        _isHarmonyRecording = true;
        _isHostRecording = false;
      } else {
        final isSupported =
            await ref.read(adbServiceProvider).isScreenRecordSupported(deviceId);
        _isHostRecording = settings.forceHostRecording || !isSupported;

        if (_isHostRecording) {
          final hostPlatform = ref.read(hostPlatformServiceProvider);
          _localRecordPath = hostPlatform.generateRecordPath(
            settings.screenshotSavePath,
            deviceId,
          );
          await File(_localRecordPath!).parent.create(recursive: true);
          _recordProcess = await ref.read(scrcpyServiceProvider).startRecording(
                deviceId: deviceId,
                localSavePath: _localRecordPath!,
              );
        } else {
          try {
            await ref
                .read(fileManagerServiceProvider)
                .delete(deviceId, '/sdcard/adb_screenrecord_temp.mp4');
          } catch (_) {}
          _recordProcess = await ref
              .read(adbServiceProvider)
              .startScreenRecord(deviceId, '/sdcard/adb_screenrecord_temp.mp4');
        }
      }

      if (_recordProcess != null) {
        final errorBuffer = StringBuffer();
        _recordProcess!.stderr.transform(utf8.decoder).listen((d) => errorBuffer.write(d));

        bool exitedEarly = false;
        int? exitCode;
        _recordProcess!.exitCode.then((code) {
          exitedEarly = true;
          exitCode = code;
          _recordTimer?.cancel();
          _recordProcess = null;
          onPhaseChanged(ScreenRecordPhase.idle);
        });

        await Future.delayed(const Duration(milliseconds: 600));
        if (exitedEarly) {
          final err = errorBuffer.toString().trim();
          throw Exception(err.isNotEmpty ? err : 'Process exited with code $exitCode');
        }
      }

      onPhaseChanged(ScreenRecordPhase.recording);

      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _duration++;
        onDurationChanged(_duration);
        if (_duration >= 180) {
          stopRecording(context: context);
        }
      });
    } catch (e) {
      _recordProcess?.kill();
      _recordProcess = null;
      _isHarmonyRecording = false;
      onPhaseChanged(ScreenRecordPhase.idle);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10n.t('error')}: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// 停止录屏并转储保存 (stopping -> saving -> idle)
  Future<void> stopRecording({required BuildContext context}) async {
    onPhaseChanged(ScreenRecordPhase.stopping);
    _recordTimer?.cancel();
    _recordTimer = null;

    try {
      if (_isHarmonyRecording) {
        onPhaseChanged(ScreenRecordPhase.saving);
        final hdc = ref.read(hdcServiceProvider);
        final stopResult = await hdc.stopScreenRecord(deviceId);
        if (!stopResult.isSuccess) {
          throw Exception(stopResult.message);
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await hdc.receiveScreenRecord(
          deviceId,
          _harmonyRecordFileName!,
          _localRecordPath!,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n
                    .t('recordSuccess')
                    .replaceAll('{path}', _localRecordPath ?? ''),
              ),
              backgroundColor: const Color(0xff09c47c),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else if (_isHostRecording) {
        if (_recordProcess != null) {
          _recordProcess?.kill();
          await _recordProcess!.exitCode;
        }
        _recordProcess = null;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n
                    .t('recordSuccess')
                    .replaceAll('{path}', _localRecordPath ?? ''),
              ),
              backgroundColor: const Color(0xff09c47c),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        await ref.read(adbServiceProvider).stopScreenRecord(deviceId);

        if (_recordProcess != null) {
          await _recordProcess!.exitCode.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              _recordProcess?.kill();
              return 0;
            },
          );
        }
        _recordProcess = null;

        await Future.delayed(const Duration(milliseconds: 500));

        onPhaseChanged(ScreenRecordPhase.saving);
        final settings = ref.read(appSettingsProvider);
        final hostPlatform = ref.read(hostPlatformServiceProvider);
        final localSavePath = hostPlatform.generateRecordPath(
          settings.screenshotSavePath,
          deviceId,
        );
        final file = File(localSavePath);
        await file.parent.create(recursive: true);

        final pullResult = await ref.read(fileManagerServiceProvider).pull(
              deviceId,
              '/sdcard/adb_screenrecord_temp.mp4',
              localSavePath,
            );

        if (pullResult.isSuccess) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n
                      .t('recordSuccess')
                      .replaceAll('{path}', localSavePath),
                ),
                backgroundColor: const Color(0xff09c47c),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          throw Exception(pullResult.stderr.isNotEmpty ? pullResult.stderr : 'Pull failed');
        }

        try {
          await ref
              .read(fileManagerServiceProvider)
              .delete(deviceId, '/sdcard/adb_screenrecord_temp.mp4');
        } catch (_) {}
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.t('recordFailed').replaceAll('{error}', '$e')),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      _isHarmonyRecording = false;
      onPhaseChanged(ScreenRecordPhase.idle);
      onDurationChanged(0);
    }
  }
}
