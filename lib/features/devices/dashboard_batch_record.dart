part of '../dashboard_screen.dart';

/// 复用现有录屏会话执行批量录屏，独立维护录屏弹窗状态。
class _BatchRecordDialog extends ConsumerStatefulWidget {
  final List<RegisteredDevice> devices;

  const _BatchRecordDialog({required this.devices});

  @override
  ConsumerState<_BatchRecordDialog> createState() => _BatchRecordDialogState();
}

class _BatchRecordDialogState extends ConsumerState<_BatchRecordDialog> {
  final Map<String, Process> _processes = {};
  final Map<String, HostRecordingBackend> _hostRecordings = {};
  final Set<String> _failedHostRecordings = {};
  Future<void>? _starting;
  bool _recording = false;
  int _duration = 0;
  Timer? _timer;
  bool _stopping = false;
  final Map<String, String> _statuses = {};
  final Map<String, bool> _isHostRecordingMap = {};
  final Map<String, String> _localRecordPaths = {};

  @override
  void initState() {
    super.initState();
    _starting = _startAll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final entry in _hostRecordings.entries) {
      entry.value.cancel();
      unawaited(entry.value.stop().then((_) async {
        final path = _localRecordPaths[entry.key];
        if (path != null && File(path).existsSync()) await File(path).delete();
      }).catchError((Object _) {}));
    }
    if (_recording) {
      // Emergency clean up of remaining recording processes
      for (final device in widget.devices) {
        if (_processes.containsKey(device.id) && _isHostRecordingMap[device.id] != true) {
          ref.read(adbServiceProvider).stopScreenRecord(device.id);
        }
      }
      for (final p in _processes.values) {
        p.kill();
      }
    }
    super.dispose();
  }

  Future<void> _startAll() async {
    setState(() {
      _recording = true;
      _duration = 0;
    });

    final settings = ref.read(appSettingsProvider);

    for (final device in widget.devices) {
      if (!mounted || _stopping) break;
      try {
        // Check if device supports screenrecord
        final isSupported = await ref
            .read(adbServiceProvider)
            .isScreenRecordSupported(device.id);

        if (!mounted || _stopping) break;
        final useHostRecord = settings.forceHostRecording || !isSupported;
        _isHostRecordingMap[device.id] = useHostRecord;

        if (useHostRecord) {
          final tempDir = Directory.systemTemp.path;
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final cleanName = device.displayName.replaceAll(RegExp(r'[^\w\-_]'), '_');
          final filename = 'screenrecord_${cleanName}_$timestamp.mp4';
          final tempPath = '$tempDir/$filename';
          _localRecordPaths[device.id] = tempPath;

          final file = File(tempPath);
          await file.parent.create(recursive: true);
          if (!mounted || _stopping) return;

          final host = _hostRecordings[device.id] = ref.read(hostRecordingFactoryProvider)(device.id, tempPath);
          await host.start();
          if (!mounted) { await host.stop(); return; }
          host.exited.then((error) {
            if (!mounted || _stopping || error == null) return;
            setState(() {
              _failedHostRecordings.add(device.id);
              _statuses[device.id] = context.l10n.t('recordFailed').replaceAll('{error}', error);
            });
            unawaited(host.stop().catchError((Object _) {}));
          });
        } else {
          // Pre-clean up any leftover temporary recording file
          try {
            await ref
                .read(fileManagerServiceProvider)
                .delete(device.id, '/sdcard/adb_batch_record_temp.mp4');
          } catch (_) {}

          final process = await ref
              .read(adbServiceProvider)
              .startScreenRecord(device.id, '/sdcard/adb_batch_record_temp.mp4');
          _processes[device.id] = process;
        }
        _statuses[device.id] = '正在录制...';
      } catch (e) {
        _failedHostRecordings.add(device.id);
        _statuses[device.id] = '录制启动失败: $e';
      }
    }

    if (!mounted || _stopping) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _duration++;
      });
      if (_processes.isNotEmpty && _duration >= 180) {
        // 3-minute limit
        _stopAll();
      }
    });
  }

  Future<void> _stopAll() async {
    if (_stopping) return;
    _timer?.cancel();
    setState(() {
      _stopping = true;
    });

    for (final host in _hostRecordings.values) { host.cancel(); }
    await _starting;
    // 各设备独立收尾，避免单个失败设备将批量等待时间放大。
    await Future.wait(_hostRecordings.entries.map((entry) async {
      try {
        await entry.value.stop();
      } catch (error) {
        _failedHostRecordings.add(entry.key);
        if (mounted) {
          _statuses[entry.key] = context.l10n.t('recordFailed').replaceAll('{error}', '$error');
        }
      }
    }));
    if (!mounted) return;

    // 1. Send SIGINT (kill -2) to all devices to properly finish recording (if not host-recording)
    for (final device in widget.devices) {
      if (_processes.containsKey(device.id) && _isHostRecordingMap[device.id] != true) {
        await ref.read(adbServiceProvider).stopScreenRecord(device.id);
      }
    }

    // 2. Wait for host process wrapper exits
    for (final entry in _processes.entries) {
      try {
        if (_isHostRecordingMap[entry.key] == true) {
          entry.value.kill();
          await entry.value.exitCode;
        } else {
          await entry.value.exitCode.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              entry.value.kill();
              return 0;
            },
          );
        }
      } catch (_) {}
    }

    // Let filesystem sync
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    // 3. Select local destination folder
    final directoryPath = await getDirectoryPath();
    if (directoryPath != null) {
      for (final device in widget.devices) {
        if ((!_processes.containsKey(device.id) && !_hostRecordings.containsKey(device.id)) ||
            _failedHostRecordings.contains(device.id)) {
          continue;
        }

        setState(() {
          _statuses[device.id] = '正在保存视频文件...';
        });

        try {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final cleanName = device.displayName.replaceAll(
            RegExp(r'[^\w\-_]'),
            '_',
          );
          final filename = 'screenrecord_${cleanName}_$timestamp.mp4';
          final localPath = '$directoryPath/$filename';

          if (_isHostRecordingMap[device.id] == true) {
            final tempPath = _localRecordPaths[device.id];
            if (tempPath != null && File(tempPath).existsSync()) {
              await File(tempPath).rename(localPath);
              _statuses[device.id] = '已保存: $filename';
            } else {
              _statuses[device.id] = '本地视频文件丢失';
            }
          } else {
            final pullRes = await ref
                .read(fileManagerServiceProvider)
                .pull(device.id, '/sdcard/adb_batch_record_temp.mp4', localPath);

            if (pullRes.isSuccess) {
              _statuses[device.id] = '已保存: $filename';
            } else {
              _statuses[device.id] = '下载失败: ${pullRes.stderr}';
            }

            // Cleanup temp file on device
            try {
              await ref
                  .read(fileManagerServiceProvider)
                  .delete(device.id, '/sdcard/adb_batch_record_temp.mp4');
            } catch (_) {}
          }
        } catch (e) {
          _statuses[device.id] = '出错: $e';
        }
      }
    } else {
      // User cancelled directory selection, clean up temp records anyway
      for (final device in widget.devices) {
        _statuses[device.id] = '用户取消保存';

        if (_isHostRecordingMap[device.id] == true) {
          final tempPath = _localRecordPaths[device.id];
          if (tempPath != null) {
            try {
              await File(tempPath).delete();
            } catch (_) {}
          }
        } else {
          try {
            await ref
                .read(fileManagerServiceProvider)
                .delete(device.id, '/sdcard/adb_batch_record_temp.mp4');
          } catch (_) {}
        }
      }
    }

    setState(() {
      _recording = false;
      _stopping = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('批量屏幕录制'),
      content: SizedBox(
        width: 500,
        height: 350,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_recording) ...[
                  const _PulsingRecordDot(),
                  const SizedBox(width: 8),
                ],
                Text(
                  _recording ? '正在录屏: ${_formatDuration(_duration)}' : '录屏已结束',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _recording ? Colors.red : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: widget.devices.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final device = widget.devices[index];
                  final status = _statuses[device.id] ?? '等待录制...';
                  final isErr = status.contains('失败') || status.contains('出错');

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.displayName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          status,
                          style: TextStyle(
                            fontSize: 12,
                            color: isErr ? Colors.red : Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (_recording)
          FilledButton.icon(
            onPressed: _stopping ? null : _stopAll,
            icon: const Icon(CupertinoIcons.stop),
            label: Text(_stopping ? '正在停止...' : '停止录屏并保存'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
          )
        else
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.t('close')),
          ),
      ],
    );
  }
}

// ==========================================
// 批量计划任务及管理器
// ==========================================
