part of '../dashboard_screen.dart';

/// 批量操作状态管理与UI实现
extension _DeviceListPanelBatchActions on _DeviceListPanelState {
  Widget _buildBatchActionsToolbar(
    BuildContext context,
    List<RegisteredDevice> checkedDevices,
  ) {
    final online = checkedDevices.where((d) => d.isOnline).toList();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            '${context.l10n.t('batchActions')} (${online.length}):',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: online.isEmpty
                      ? null
                      : () => _handleBatchMirror(context, online),
                  icon: const Icon(CupertinoIcons.tv, size: 16),
                  label: Text(context.l10n.t('batchMirror')),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: online.isEmpty
                      ? null
                      : () => _handleBatchScreenshot(context, online),
                  icon: const Icon(CupertinoIcons.camera, size: 16),
                  label: Text(context.l10n.t('batchScreenshot')),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: online.isEmpty
                      ? null
                      : () => _handleBatchRecord(context, online),
                  icon: const Icon(CupertinoIcons.videocam, size: 16),
                  label: Text(context.l10n.t('batchRecord')),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: online.isEmpty
                      ? null
                      : () => _handleBatchInstall(context, online),
                  icon: const Icon(CupertinoIcons.square_arrow_down, size: 16),
                  label: Text(context.l10n.t('batchInstall')),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: online.isEmpty
                      ? null
                      : () => _handleBatchPush(context, online),
                  icon: const Icon(CupertinoIcons.folder_badge_plus, size: 16),
                  label: Text(context.l10n.t('batchPush')),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: online.isEmpty
                      ? null
                      : () => _handleBatchScript(context, online),
                  icon: const Icon(CupertinoIcons.doc_text, size: 16),
                  label: Text(context.l10n.t('batchScript')),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: online.isEmpty
                      ? null
                      : () => _handleBatchSchedule(context, online),
                  icon: const Icon(CupertinoIcons.clock, size: 16),
                  label: Text(context.l10n.t('batchSchedule')),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: checkedDevices.isEmpty
                      ? null
                      : () => _deleteSelectedDevices(
                          context,
                          checkedDevices.length,
                        ),
                  icon: const Icon(CupertinoIcons.trash, size: 16),
                  label: Text(context.l10n.t('deleteSelectedDevices')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 批量镜像操作
  Future<void> _handleBatchMirror(
    BuildContext context,
    List<RegisteredDevice> devices,
  ) async {
    int started = 0;
    for (final device in devices) {
      try {
        // 1. 如果该设备在主窗口已经开启了内嵌投屏，先停止它
        final textureId = ref.read(activeEmbeddedMirrorProvider(device.id));
        if (textureId != null) {
          await ref
              .read(activeEmbeddedMirrorProvider(device.id).notifier)
              .forceStop();
        }

        // 2. 开启独立投屏窗口
        final overviewAsync = ref.read(deviceOverviewProvider(device.id));
        final resolution = overviewAsync.maybeWhen(
          data: (overview) => overview.physicalResolution,
          orElse: () => null,
        );
        final initialSize = _resolveMirrorInitialWindowSize(resolution);
        await createAdbManageWindow(
          arguments: {
            'type': 'mirror',
            'deviceId': device.id,
            'deviceName': device.displayName,
          },
          frame: Offset.zero & initialSize,
          title: '投屏 - ${device.displayName}',
        );
        started++;
      } catch (e) {
        debugPrint('Mirror failed for ${device.id}: $e');
      }
    }
    if (context.mounted) {
      _showSnack(context, '已成功对 $started 台设备开启镜像投影');
    }
  }

  /// 批量截图操作
  Future<void> _handleBatchScreenshot(
    BuildContext context,
    List<RegisteredDevice> devices,
  ) async {
    final directoryPath = await getDirectoryPath();
    if (directoryPath == null) return;

    if (!context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BatchProgressDialog(
        title: '批量截取屏幕',
        devices: devices,
        action: (device) async {
          final bytes = await ref
              .read(adbServiceProvider)
              .captureScreenshot(device.id);
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final cleanName = device.displayName.replaceAll(
            RegExp(r'[^\w\-_]'),
            '_',
          );
          final filename = 'screenshot_${cleanName}_$timestamp.png';
          final file = File('$directoryPath/$filename');
          await file.writeAsBytes(bytes);
          return '保存成功: $filename';
        },
      ),
    );
  }

  /// 批量录屏操作
  Future<void> _handleBatchRecord(
    BuildContext context,
    List<RegisteredDevice> devices,
  ) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BatchRecordDialog(devices: devices),
    );
  }

  /// 批量安装应用操作
  Future<void> _handleBatchInstall(
    BuildContext context,
    List<RegisteredDevice> devices,
  ) async {
    const group = XTypeGroup(label: 'APK', extensions: ['apk']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;

    if (!context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BatchProgressDialog(
        title: '批量安装应用',
        devices: devices,
        action: (device) async {
          final res = await ref
              .read(appManagementServiceProvider)
              .installApk(device.id, file.path);
          if (res.isSuccess) {
            return '安装成功';
          } else {
            throw Exception(
              res.stderr.isNotEmpty
                  ? res.stderr.trim()
                  : '安装失败 (代码 ${res.exitCode})',
            );
          }
        },
      ),
    );
  }

  /// 批量推送文件操作
  Future<void> _handleBatchPush(
    BuildContext context,
    List<RegisteredDevice> devices,
  ) async {
    final targetPathController = TextEditingController(
      text: '/sdcard/Download/',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量推送文件'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请指定推送到设备的目录：'),
            const SizedBox(height: 8),
            TextField(
              controller: targetPathController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '/sdcard/Download/',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.l10n.t('confirm')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final files = await openFiles();
    if (files.isEmpty) return;

    if (!context.mounted) return;

    final targetPath = targetPathController.text.trim();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BatchProgressDialog(
        title: '批量推送文件',
        devices: devices,
        action: (device) async {
          final buffer = StringBuffer();
          for (final file in files) {
            final filename = file.name;
            final remoteFile = targetPath.endsWith('/')
                ? '$targetPath$filename'
                : '$targetPath/$filename';
            final res = await ref
                .read(fileManagerServiceProvider)
                .push(device.id, file.path, remoteFile);
            if (!res.isSuccess) {
              throw Exception('推送 $filename 失败: ${res.stderr}');
            }
            buffer.writeln('推送 $filename 成功');
          }
          return buffer.toString().trim();
        },
      ),
    );
  }

  /// 批量执行脚本操作
  Future<void> _handleBatchScript(
    BuildContext context,
    List<RegisteredDevice> devices,
  ) async {
    final scriptController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量执行脚本'),
        content: SizedBox(
          width: 550,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('请输入要在各设备上执行的 ADB shell 命令 (多行命令请换行)：'),
              const SizedBox(height: 8),
              TextField(
                controller: scriptController,
                maxLines: 6,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText:
                      'echo "Hello World"\npm list packages\ngetprop ro.product.model',
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(CupertinoIcons.folder_open, size: 16),
                  label: const Text('从本地脚本文件导入'),
                  onPressed: () async {
                    const group = XTypeGroup(
                      label: 'Script',
                      extensions: ['sh', 'txt', 'bat'],
                    );
                    final file = await openFile(acceptedTypeGroups: [group]);
                    if (file != null) {
                      final content = await File(file.path).readAsString();
                      scriptController.text = content;
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('运行'),
          ),
        ],
      ),
    );

    if (confirmed != true || scriptController.text.trim().isEmpty) return;

    if (!context.mounted) return;

    final script = scriptController.text.trim();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BatchProgressDialog(
        title: '批量执行脚本',
        devices: devices,
        action: (device) async {
          final res = await ref
              .read(adbServiceProvider)
              .shell(device.id, script);
          if (res.isSuccess) {
            return res.stdout.isEmpty ? '执行完成 (无输出)' : res.stdout.trim();
          } else {
            throw Exception(
              res.stderr.isNotEmpty
                  ? res.stderr.trim()
                  : '执行失败 (代码 ${res.exitCode})',
            );
          }
        },
      ),
    );
  }

  /// 批量计划任务配置弹窗
  Future<void> _handleBatchSchedule(
    BuildContext context,
    List<RegisteredDevice> devices,
  ) async {
    showDialog<void>(
      context: context,
      builder: (ctx) => _BatchScheduleDialog(devices: devices),
    );
  }
}

// ==========================================
// 批量任务进度通用弹窗
// ==========================================
enum _BatchItemStatus { pending, running, success, failed }

class _BatchItemProgress {
  final RegisteredDevice device;
  _BatchItemStatus status;
  String message;

  _BatchItemProgress({required this.device})
    : status = _BatchItemStatus.pending,
      message = '';
}

class _BatchProgressDialog extends ConsumerStatefulWidget {
  final String title;
  final List<RegisteredDevice> devices;
  final Future<String> Function(RegisteredDevice device) action;

  const _BatchProgressDialog({
    required this.title,
    required this.devices,
    required this.action,
  });

  @override
  ConsumerState<_BatchProgressDialog> createState() =>
      _BatchProgressDialogState();
}

class _BatchProgressDialogState extends ConsumerState<_BatchProgressDialog> {
  late List<_BatchItemProgress> _items;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _items = widget.devices.map((d) => _BatchItemProgress(device: d)).toList();
    _runActions();
  }

  Future<void> _runActions() async {
    final futures = <Future<void>>[];
    for (var i = 0; i < _items.length; i++) {
      final index = i;
      futures.add(() async {
        if (!mounted) return;
        setState(() {
          _items[index].status = _BatchItemStatus.running;
          _items[index].message = '正在执行...';
        });
        try {
          final res = await widget.action(_items[index].device);
          if (mounted) {
            setState(() {
              _items[index].status = _BatchItemStatus.success;
              _items[index].message = res;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _items[index].status = _BatchItemStatus.failed;
              _items[index].message = e.toString().replaceFirst(
                'Exception: ',
                '',
              );
            });
          }
        }
      }());
    }
    await Future.wait(futures);
    if (mounted) {
      setState(() {
        _finished = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 500,
        height: 350,
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  Widget statusIcon = const Icon(
                    CupertinoIcons.clock,
                    color: Colors.grey,
                    size: 18,
                  );
                  if (item.status == _BatchItemStatus.running) {
                    statusIcon = const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  } else if (item.status == _BatchItemStatus.success) {
                    statusIcon = const Icon(
                      CupertinoIcons.check_mark_circled_solid,
                      color: Colors.green,
                      size: 18,
                    );
                  } else if (item.status == _BatchItemStatus.failed) {
                    statusIcon = const Icon(
                      CupertinoIcons.exclamationmark_circle_fill,
                      color: Colors.red,
                      size: 18,
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        statusIcon,
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.device.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.message.isEmpty ? '等待执行...' : item.message,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: item.status == _BatchItemStatus.failed
                                      ? Colors.red
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
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
        TextButton(
          onPressed: _finished ? () => Navigator.of(context).pop() : null,
          child: Text(_finished ? context.l10n.t('close') : '正在执行...'),
        ),
      ],
    );
  }
}

// ==========================================
// 批量录屏专用弹窗
// ==========================================
class _BatchRecordDialog extends ConsumerStatefulWidget {
  final List<RegisteredDevice> devices;

  const _BatchRecordDialog({required this.devices});

  @override
  ConsumerState<_BatchRecordDialog> createState() => _BatchRecordDialogState();
}

class _BatchRecordDialogState extends ConsumerState<_BatchRecordDialog> {
  final Map<String, Process> _processes = {};
  bool _recording = false;
  int _duration = 0;
  Timer? _timer;
  bool _stopping = false;
  final Map<String, String> _statuses = {};

  @override
  void initState() {
    super.initState();
    _startAll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_recording) {
      // Emergency clean up of remaining recording processes
      for (final device in widget.devices) {
        ref.read(adbServiceProvider).stopScreenRecord(device.id);
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

    for (final device in widget.devices) {
      try {
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
        _statuses[device.id] = '正在录制...';
      } catch (e) {
        _statuses[device.id] = '录制启动失败: $e';
      }
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _duration++;
      });
      if (_duration >= 180) {
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

    // 1. Send SIGINT (kill -2) to all devices to properly finish recording
    for (final device in widget.devices) {
      if (_processes.containsKey(device.id)) {
        await ref.read(adbServiceProvider).stopScreenRecord(device.id);
      }
    }

    // 2. Wait for host process wrapper exits
    for (final entry in _processes.entries) {
      try {
        await entry.value.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            entry.value.kill();
            return 0;
          },
        );
      } catch (_) {}
    }

    // Let filesystem sync
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    // 3. Select local destination folder
    final directoryPath = await getDirectoryPath();
    if (directoryPath != null) {
      for (final device in widget.devices) {
        if (!_processes.containsKey(device.id)) continue;

        setState(() {
          _statuses[device.id] = '正在下载视频文件...';
        });

        try {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final cleanName = device.displayName.replaceAll(
            RegExp(r'[^\w\-_]'),
            '_',
          );
          final filename = 'screenrecord_${cleanName}_$timestamp.mp4';
          final localPath = '$directoryPath/$filename';

          final pullRes = await ref
              .read(fileManagerServiceProvider)
              .pull(device.id, '/sdcard/adb_batch_record_temp.mp4', localPath);

          if (pullRes.isSuccess) {
            _statuses[device.id] = '已保存: $filename';
          } else {
            _statuses[device.id] = '下载失败: ${pullRes.stderr}';
          }
        } catch (e) {
          _statuses[device.id] = '出错: $e';
        }

        // Cleanup temp file on device
        try {
          await ref
              .read(fileManagerServiceProvider)
              .delete(device.id, '/sdcard/adb_batch_record_temp.mp4');
        } catch (_) {}
      }
    } else {
      // User cancelled directory selection, clean up device temp records anyway
      for (final device in widget.devices) {
        _statuses[device.id] = '用户取消保存';
        try {
          await ref
              .read(fileManagerServiceProvider)
              .delete(device.id, '/sdcard/adb_batch_record_temp.mp4');
        } catch (_) {}
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
class ScheduledTask {
  final String id;
  final String title;
  final String actionType; // 'screenshot', 'install', 'push', 'script'
  final List<String> targetDeviceIds;
  final DateTime scheduledTime;
  final dynamic payload;
  String status; // 'pending', 'running', 'completed', 'failed', 'cancelled'
  String result;

  ScheduledTask({
    required this.id,
    required this.title,
    required this.actionType,
    required this.targetDeviceIds,
    required this.scheduledTime,
    required this.payload,
    this.status = 'pending',
    this.result = '',
  });
}

class ScheduledTasksNotifier extends Notifier<List<ScheduledTask>> {
  final Map<String, Timer> _timers = {};

  @override
  List<ScheduledTask> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
    });
    return [];
  }

  void scheduleTask(ScheduledTask task, Future<String> Function() execute) {
    state = [...state, task];
    final delay = task.scheduledTime.difference(DateTime.now());
    if (delay.isNegative) {
      _executeTask(task.id, execute);
      return;
    }
    final timer = Timer(delay, () {
      _executeTask(task.id, execute);
    });
    _timers[task.id] = timer;
  }

  void cancelTask(String id) {
    _timers[id]?.cancel();
    _timers.remove(id);
    state = state
        .map((t) => t.id == id ? t.copyWithStatus('cancelled', '已取消') : t)
        .toList();
  }

  Future<void> _executeTask(
    String id,
    Future<String> Function() execute,
  ) async {
    _timers.remove(id);
    state = state
        .map((t) => t.id == id ? t.copyWithStatus('running', '正在执行...') : t)
        .toList();

    try {
      final summary = await execute();
      state = state
          .map((t) => t.id == id ? t.copyWithStatus('completed', summary) : t)
          .toList();
    } catch (e) {
      state = state
          .map((t) => t.id == id ? t.copyWithStatus('failed', '执行出错: $e') : t)
          .toList();
    }
  }
}

extension ScheduledTaskExtension on ScheduledTask {
  ScheduledTask copyWithStatus(String newStatus, String newResult) {
    return ScheduledTask(
      id: id,
      title: title,
      actionType: actionType,
      targetDeviceIds: targetDeviceIds,
      scheduledTime: scheduledTime,
      payload: payload,
      status: newStatus,
      result: newResult,
    );
  }
}

final scheduledTasksProvider =
    NotifierProvider<ScheduledTasksNotifier, List<ScheduledTask>>(
      ScheduledTasksNotifier.new,
    );

class _BatchScheduleDialog extends ConsumerStatefulWidget {
  final List<RegisteredDevice> devices;

  const _BatchScheduleDialog({required this.devices});

  @override
  ConsumerState<_BatchScheduleDialog> createState() =>
      _BatchScheduleDialogState();
}

class _BatchScheduleDialogState extends ConsumerState<_BatchScheduleDialog> {
  int _delayMinutes = 1;
  String _selectedAction =
      'screenshot'; // 'screenshot', 'install', 'push', 'script'

  // Custom action parameters
  String _apkPath = '';
  List<String> _pushFilePaths = [];
  String _pushTargetPath = '/sdcard/Download/';
  String _scriptText = '';
  late final TextEditingController _pushTargetPathController;

  @override
  void initState() {
    super.initState();
    _pushTargetPathController = TextEditingController(text: _pushTargetPath);
  }

  @override
  void dispose() {
    _pushTargetPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(scheduledTasksProvider);

    return DefaultTabController(
      length: 2,
      child: AlertDialog(
        title: const Text('批量计划任务'),
        content: SizedBox(
          width: 600,
          height: 400,
          child: Column(
            children: [
              const TabBar(
                labelColor: Colors.blue,
                unselectedLabelColor: Colors.grey,
                tabs: [
                  Tab(text: '创建新任务'),
                  Tab(text: '任务管理列表'),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  children: [_buildCreateTaskTab(), _buildTaskListTab(tasks)],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.t('close')),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateTaskTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('延时执行时间: '),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _delayMinutes,
                items: [1, 2, 5, 10, 30, 60].map((m) {
                  return DropdownMenuItem<int>(value: m, child: Text('$m 分钟后'));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _delayMinutes = val);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedAction,
            decoration: const InputDecoration(
              labelText: '执行操作',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'screenshot', child: Text('批量截图')),
              DropdownMenuItem(value: 'install', child: Text('批量安装APP')),
              DropdownMenuItem(value: 'push', child: Text('批量推送文件')),
              DropdownMenuItem(value: 'script', child: Text('批量执行脚本')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _selectedAction = val);
            },
          ),
          const SizedBox(height: 16),
          _buildActionFields(),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton(
              onPressed: _onCreateTask,
              child: const Text('创建并启动计划'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionFields() {
    switch (_selectedAction) {
      case 'screenshot':
        return const Text('截图结果将自动保存至您的默认下载目录中。');
      case 'install':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                const group = XTypeGroup(label: 'APK', extensions: ['apk']);
                final file = await openFile(acceptedTypeGroups: [group]);
                if (file != null) {
                  setState(() => _apkPath = file.path);
                }
              },
              icon: const Icon(CupertinoIcons.folder_open),
              label: const Text('选择本地 APK 文件'),
            ),
            if (_apkPath.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('已选择: $_apkPath', style: const TextStyle(fontSize: 12)),
            ],
          ],
        );
      case 'push':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final files = await openFiles();
                if (files.isNotEmpty) {
                  setState(
                    () => _pushFilePaths = files.map((f) => f.path).toList(),
                  );
                }
              },
              icon: const Icon(CupertinoIcons.folder_open),
              label: const Text('选择本地文件'),
            ),
            if (_pushFilePaths.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '已选择 ${_pushFilePaths.length} 个文件',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: '手机目标路径',
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => _pushTargetPath = val,
              controller: _pushTargetPathController,
            ),
          ],
        );
      case 'script':
        return TextField(
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: '执行命令脚本',
            border: OutlineInputBorder(),
            hintText: 'getprop ro.product.model',
          ),
          onChanged: (val) => _scriptText = val,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTaskListTab(List<ScheduledTask> tasks) {
    if (tasks.isEmpty) {
      return const Center(child: Text('暂无计划任务'));
    }
    return ListView.separated(
      itemCount: tasks.length,
      separatorBuilder: (ctx, idx) => const Divider(),
      itemBuilder: (ctx, idx) {
        final task = tasks[idx];
        final remaining = task.scheduledTime.difference(DateTime.now());
        final isPending = task.status == 'pending';

        String timeDisplay = '已执行';
        if (remaining.inSeconds > 0) {
          timeDisplay = '剩余 ${remaining.inSeconds} 秒';
        }

        return ListTile(
          title: Text(task.title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('状态: ${task.status} (${task.result})'),
              Text(
                '设备数: ${task.targetDeviceIds.length} 台 | 计划执行时间: ${task.scheduledTime.toLocal()}',
              ),
            ],
          ),
          trailing: isPending
              ? ElevatedButton(
                  onPressed: () => ref
                      .read(scheduledTasksProvider.notifier)
                      .cancelTask(task.id),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('取消'),
                )
              : Text(
                  timeDisplay,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
        );
      },
    );
  }

  Future<void> _onCreateTask() async {
    final targetDevices = widget.devices;
    final scheduledTime = DateTime.now().add(Duration(minutes: _delayMinutes));
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    String title = '';
    Future<String> Function() execute;
    dynamic payload;

    switch (_selectedAction) {
      case 'screenshot':
        title = '批量截图';
        execute = () async {
          final home =
              Platform.environment['HOME'] ?? Directory.systemTemp.path;
          final saveDir = '$home/Downloads';
          final dir = Directory(saveDir);
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          int success = 0;
          for (final d in targetDevices) {
            try {
              final bytes = await ref
                  .read(adbServiceProvider)
                  .captureScreenshot(d.id);
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              final file = File('$saveDir/screenshot_${d.id}_$timestamp.png');
              await file.writeAsBytes(bytes);
              success++;
            } catch (_) {}
          }
          return '$success台成功，已保存至 Downloads';
        };
        break;

      case 'install':
        if (_apkPath.isEmpty) return;
        title = '批量安装应用';
        payload = _apkPath;
        execute = () async {
          int success = 0;
          for (final d in targetDevices) {
            try {
              final res = await ref
                  .read(appManagementServiceProvider)
                  .installApk(d.id, _apkPath);
              if (res.isSuccess) success++;
            } catch (_) {}
          }
          return '$success台安装成功';
        };
        break;

      case 'push':
        if (_pushFilePaths.isEmpty) return;
        final targetPath = _pushTargetPathController.text.trim();
        title = '批量推送文件';
        payload = {'files': _pushFilePaths, 'target': targetPath};
        execute = () async {
          int success = 0;
          for (final d in targetDevices) {
            bool devOk = true;
            for (final f in _pushFilePaths) {
              final filename = f.split('/').last;
              final remoteFile = targetPath.endsWith('/')
                  ? '$targetPath$filename'
                  : '$targetPath/$filename';
              final res = await ref
                  .read(fileManagerServiceProvider)
                  .push(d.id, f, remoteFile);
              if (!res.isSuccess) devOk = false;
            }
            if (devOk) success++;
          }
          return '$success台推送成功';
        };
        break;

      case 'script':
        if (_scriptText.trim().isEmpty) return;
        title = '批量执行命令';
        payload = _scriptText;
        execute = () async {
          int success = 0;
          for (final d in targetDevices) {
            try {
              final res = await ref
                  .read(adbServiceProvider)
                  .shell(d.id, _scriptText);
              if (res.isSuccess) success++;
            } catch (_) {}
          }
          return '$success台执行完成';
        };
        break;

      default:
        return;
    }

    final task = ScheduledTask(
      id: id,
      title: title,
      actionType: _selectedAction,
      targetDeviceIds: targetDevices.map((d) => d.id).toList(),
      scheduledTime: scheduledTime,
      payload: payload,
    );

    ref.read(scheduledTasksProvider.notifier).scheduleTask(task, execute);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('计划任务已成功创建，将于 $_delayMinutes 分钟后执行。'),
          backgroundColor: const Color(0xff09c47c),
        ),
      );
      Navigator.of(context).pop();
    }
  }
}
