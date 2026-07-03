part of '../dashboard_screen.dart';

mixin _ScreenRecordMixin on ConsumerState<_ScreenshotTab> {
  Process? _recordProcess;
  bool _isRecording = false;
  int _recordDuration = 0;
  Timer? _recordTimer;
  bool _isManuallyStopping = false;

  bool get isRecording => _isRecording;
  bool get isManuallyStopping => _isManuallyStopping;
  int get recordDuration => _recordDuration;

  void _cleanupRecord() {
    _recordTimer?.cancel();
    if (_isRecording) {
      ref.read(adbServiceProvider).stopScreenRecord(widget.device.id);
      _recordProcess?.kill();
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;

    final state = this as _ScreenshotTabState;

    // Stop auto-refresh if enabled to prevent conflict
    if (state._autoRefresh) {
      state._toggleAutoRefresh();
    }

    try {
      // Pre-clean up any leftover temporary recording file
      try {
        await ref
            .read(fileManagerServiceProvider)
            .delete(widget.device.id, '/sdcard/adb_screenrecord_temp.mp4');
      } catch (_) {}

      _recordProcess = await ref
          .read(adbServiceProvider)
          .startScreenRecord(
            widget.device.id,
            '/sdcard/adb_screenrecord_temp.mp4',
          );

      final errorBuffer = StringBuffer();
      _recordProcess!.stderr.transform(utf8.decoder).listen((data) {
        errorBuffer.write(data);
      });

      bool exitedEarly = false;
      int? exitCode;

      _recordProcess!.exitCode.then((code) {
        exitedEarly = true;
        exitCode = code;
        if (_isRecording) {
          _handleRecordEndedEarly(code, errorBuffer.toString());
        }
      });

      // Wait a short time to see if the process exits immediately
      await Future.delayed(const Duration(milliseconds: 600));
      if (exitedEarly) {
        final err = errorBuffer.toString().trim();
        throw Exception(
          err.isNotEmpty ? err : 'screenrecord exited with code $exitCode',
        );
      }

      setState(() {
        _isRecording = true;
        _recordDuration = 0;
        _isManuallyStopping = false;
      });

      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordDuration++;
        });
        if (_recordDuration >= 180) {
          // 3-minute limit
          _stopRecording();
        }
      });
    } catch (e) {
      _recordProcess?.kill();
      _recordProcess = null;
      _isRecording = false;

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.l10n.t('error')),
            content: Text('${context.l10n.t('recordFailedHint')}\n\n详细信息: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.t('close')),
              ),
            ],
          ),
        );
      }
    }
  }

  void _handleRecordEndedEarly(int code, String errorMsg) {
    if (!mounted) return;

    // exit code 130 is SIGINT termination, which is normal stop
    final isNormal = code == 0 || code == 130;

    if (_isRecording && !isNormal && !_isManuallyStopping) {
      setState(() {
        _isRecording = false;
        _recordTimer?.cancel();
        _recordTimer = null;
        _recordProcess = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.l10n.t('recordFailed')}: ${errorMsg.trim()} ($code)',
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording || _isManuallyStopping) return;

    setState(() {
      _isManuallyStopping = true;
      _recordTimer?.cancel();
      _recordTimer = null;
    });

    final state = this as _ScreenshotTabState;

    try {
      // 1. Send stop command (SIGINT) to device
      await ref.read(adbServiceProvider).stopScreenRecord(widget.device.id);

      // 2. Wait for process exit on host
      if (_recordProcess != null) {
        await _recordProcess!.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            _recordProcess?.kill();
            return 0;
          },
        );
      }

      // Small delay for device file write completion
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      // 3. Save directly
      final settings = ref.read(appSettingsProvider);
      final hostPlatform = ref.read(hostPlatformServiceProvider);
      final localSavePath = hostPlatform.generateRecordPath(
        settings.screenshotSavePath,
        widget.device.id,
      );
      final file = File(localSavePath);
      await file.parent.create(recursive: true);

      setState(() {
        state._loading = true;
      });

      // 4. Pull file
      final pullResult = await ref
          .read(fileManagerServiceProvider)
          .pull(
            widget.device.id,
            '/sdcard/adb_screenrecord_temp.mp4',
            localSavePath,
          );

      if (pullResult.isSuccess) {
        if (mounted) {
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
        throw Exception(
          pullResult.stderr.isNotEmpty
              ? pullResult.stderr
              : 'File transfer failed',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10n.t('recordFailed')}: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      // 5. Clean up device temporary file
      try {
        await ref
            .read(fileManagerServiceProvider)
            .delete(widget.device.id, '/sdcard/adb_screenrecord_temp.mp4');
      } catch (e) {
        debugPrint('Failed to delete temp record file on device: $e');
      }

      if (mounted) {
        setState(() {
          _isRecording = false;
          _isManuallyStopping = false;
          state._loading = false;
          _recordProcess = null;
        });
      }
    }
  }
}

class _PulsingRecordDot extends StatefulWidget {
  const _PulsingRecordDot();

  @override
  State<_PulsingRecordDot> createState() => _PulsingRecordDotState();
}

class _PulsingRecordDotState extends State<_PulsingRecordDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

String _formatDuration(int seconds) {
  final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
  final secs = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$secs';
}
