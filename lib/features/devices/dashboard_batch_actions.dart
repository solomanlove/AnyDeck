part of '../dashboard_screen.dart';

/// 批量操作状态管理与UI实现
extension _DeviceListPanelBatchActions on _DeviceListPanelState {
  /// 批量镜像操作
  Future<void> _handleBatchMirror(
    BuildContext context,
    List<RegisteredDevice> devices,
  ) async {
    final titleTemplate = context.l10n.t('screenMirrorTitle');
    int started = 0;
    for (final device in devices) {
      final windowTitle = titleTemplate.replaceAll('{name}', device.displayName);
      try {
        // 1. 如果该设备在主窗口已经开启了内嵌投屏，先停止它
        final textureId = ref.read(activeEmbeddedMirrorProvider(device.id));
        if (textureId != null) {
          await ref
              .read(activeEmbeddedMirrorProvider(device.id).notifier)
              .forceStop();
        }

        // 2. 开启独立投屏窗口
        final aspect =
            await MirrorAspectResolver.fetchDeviceAspectRatioBeforeMirror(
          ref: ref,
          deviceId: device.id,
          isHarmony: device.isHarmony,
          isIos: device.isIos,
        );
        final overviewAsync = ref.read(deviceOverviewProvider(device.id));
        final resolution = overviewAsync.maybeWhen(
          data: (overview) => overview.physicalResolution,
          orElse: () => null,
        );
        final initialSize =
            resolveMirrorInitialWindowSize(resolution, ratio: aspect);
        await createAdbManageWindow(
          arguments: {
            'type': 'mirror',
            'deviceId': device.id,
            'physicalDeviceKey': FusionModePreference.knownPhysicalKey(device, device.id),
            'deviceName': device.displayName,
            'alwaysOnTop': ref.read(appSettingsProvider).scrcpyAlwaysOnTop,
            'isIos': device.isIos,
            'isHarmony': device.isHarmony,
          },
          frame: Offset.zero & initialSize,
          title: windowTitle,
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
          // 统一经 HDC 服务选择原生或自定义 CLI，避免绕过设置中的工具路径。
          if (device.isHarmony) {
            final res = await ref
                .read(hdcServiceProvider)
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
          }

          // 显式配置 ADB 时必须经当前 CLI；默认环境保留 Direct Socket 优化。
          const cliTimeout = Duration(seconds: 15);
          var fallbackTimeout = cliTimeout;
          if (!device.isIos &&
              !device.isHarmony &&
              !hasUserToolPath('adb') &&
              RustDalBridge.instance.supportsTimedShell) {
            const timeout = Duration(seconds: 30);
            final elapsed = Stopwatch()..start();
            try {
              final out = await RustDalBridge.instance.executeShell(
                device.id,
                script,
                platform: DevicePlatform.android,
                timeout: timeout,
              );
              return out.isEmpty ? '执行完成 (无输出)' : out.trim();
            } catch (_) {
              // 只用剩余预算回退 CLI，避免慢脚本超时后再次执行。
              final remaining = timeout - elapsed.elapsed;
              if (remaining <= Duration.zero) rethrow;
              if (remaining < cliTimeout) fallbackTimeout = remaining;
            }
          }
          final res = await ref
              .read(adbServiceProvider)
              .shell(device.id, script, timeout: fallbackTimeout);
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
