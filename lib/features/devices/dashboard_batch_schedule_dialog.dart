part of '../dashboard_screen.dart';

/// 配置批量计划的目标、动作及执行时间，与执行模型分离。
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
    final tasks = ref.watch(scheduledDeviceTasksProvider);

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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _delayMinutes,
                    borderRadius: BorderRadius.circular(12),
                    icon: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(CupertinoIcons.chevron_down, size: 16),
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    items: [1, 2, 5, 10, 30, 60].map((m) {
                      return DropdownMenuItem<int>(value: m, child: Text('$m 分钟后'));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _delayMinutes = val);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedAction,
            borderRadius: BorderRadius.circular(12),
            icon: const Icon(CupertinoIcons.chevron_down, size: 16),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
            decoration: const InputDecoration(
              labelText: '执行操作',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
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

  Widget _buildTaskListTab(List<ScheduledDeviceTask> tasks) {
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
                      .read(scheduledDeviceTasksProvider.notifier)
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

    final task = ScheduledDeviceTask(
      id: id,
      title: title,
      actionType: _selectedAction,
      targetDeviceIds: targetDevices.map((d) => d.id).toList(),
      scheduledTime: scheduledTime,
      payload: payload,
    );

    ref.read(scheduledDeviceTasksProvider.notifier).scheduleTask(task, execute);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('计划任务已成功创建，将于 $_delayMinutes 分钟后执行。'),
          backgroundColor: AppPalette.primary,
        ),
      );
      Navigator.of(context).pop();
    }
  }
}
