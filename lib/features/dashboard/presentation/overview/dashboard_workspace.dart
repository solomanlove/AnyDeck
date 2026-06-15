part of '../dashboard_screen.dart';

class _WorkspacePanel extends ConsumerWidget {
  const _WorkspacePanel({required this.selectedDevice, required this.sessions});

  final AdbDevice? selectedDevice;
  final Map<String, ScrcpySession> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = selectedDevice;

    if (device == null) {
      return const SizedBox.shrink();
    }

    final tabIndex = ref.watch(selectedToolTabProvider);

    // 监听端口转发自动应用服务
    ref.watch(portForwardAutoApplyProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 同一个 workspace 可能处在有界的桌面 Row 中，也可能处在无界的
        // 移动端 ListView 中，因此 tab 卡片需要不同的高度策略。
        final hasBoundedHeight = constraints.hasBoundedHeight;

        final content = _ToolContentCard(
          device: device,
          sessions: sessions,
          tabIndex: tabIndex,
        );

        return DragDropTargetOverlay(
          onDragDone: (files) => _handleDrop(context, ref, device, files),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SelectedDeviceHeader(device: device),
              if (hasBoundedHeight)
                Expanded(child: content)
              else
                SizedBox(height: 800, child: content),
            ],
          ),
        );
      },
    );
  }

  /// 处理桌面拖拽：APK 文件执行安装，其他文件执行上传。
  Future<void> _handleDrop(
    BuildContext context,
    WidgetRef ref,
    AdbDevice device,
    List<XFile> files,
  ) async {
    if (files.isEmpty) {
      return;
    }
    final isOnline = ref.read(deviceOnlineProvider(device.id));
    if (!isOnline) {
      _showSnack(
        context,
        context.l10n.t('offlineDragInstallWarning'),
        isError: true,
      );
      return;
    }
    final appService = ref.read(appManagementServiceProvider);
    final fileService = ref.read(fileManagerServiceProvider);
    final remotePath = ref.read(remotePathProvider);
    final transferNotifier = ref.read(transferListProvider.notifier);

    for (final file in files) {
      final isApk = file.path.toLowerCase().endsWith('.apk');
      final taskId = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';

      transferNotifier.addTask(
        TransferTask(
          id: taskId,
          name: file.name,
          deviceId: device.id,
          isApk: isApk,
        ),
      );

      try {
        final result = isApk
            ? await appService.installApk(device.id, file.path)
            : await fileService.push(device.id, file.path, remotePath);

        transferNotifier.updateTask(
          id: taskId,
          isDone: true,
          isSuccess: result.isSuccess,
          error: result.isSuccess ? null : result.message,
        );

        if (!context.mounted) {
          return;
        }

        final message = isApk
            ? (result.isSuccess
                  ? context.l10n
                        .t('apkInstallSuccess')
                        .replaceAll('{name}', file.name)
                  : context.l10n
                        .t('apkInstallFailed')
                        .replaceAll('{name}', file.name)
                        .replaceAll('{error}', result.message))
            : (result.isSuccess
                  ? context.l10n
                        .t('fileUploadSuccess')
                        .replaceAll('{name}', file.name)
                  : context.l10n
                        .t('fileUploadFailed')
                        .replaceAll('{name}', file.name)
                        .replaceAll('{error}', result.message));

        _showSnack(context, message, isError: !result.isSuccess);
      } catch (e) {
        transferNotifier.updateTask(
          id: taskId,
          isDone: true,
          isSuccess: false,
          error: e.toString(),
        );
        if (context.mounted) {
          _showSnack(context, '${file.name}: $e', isError: true);
        }
      }
    }
    await ref.read(appManagementServiceProvider).clearPackageCache(device.id);
    ref.invalidate(packagesProvider(device.id));
    ref.invalidate(
      remoteFilesProvider(
        RemoteDirectoryRequest(deviceId: device.id, path: remotePath),
      ),
    );
  }
}

class _ToolContentCard extends StatefulWidget {
  const _ToolContentCard({
    required this.device,
    required this.sessions,
    required this.tabIndex,
  });

  final AdbDevice device;
  final Map<String, ScrcpySession> sessions;
  final int tabIndex;

  @override
  State<_ToolContentCard> createState() => _ToolContentCardState();
}

class _ToolContentCardState extends State<_ToolContentCard> {
  // 记录已经访问并初始化的 tab 索引，实现懒加载
  final Set<int> _initializedTabs = {};
  late int _currentToolIndex;

  @override
  void initState() {
    super.initState();
    // 确保初始索引在有效范围内 (0-11)
    _currentToolIndex = widget.tabIndex < 12 ? widget.tabIndex : 0;
    _initializedTabs.add(_currentToolIndex);
  }

  @override
  void didUpdateWidget(covariant _ToolContentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果设备切换了，清空已初始化的 Tab 状态，释放资源
    if (oldWidget.device.id != widget.device.id) {
      _initializedTabs.clear();
    }
    // 当 widget.tabIndex 为 12 (即设置 Tab) 时，忽略更新，保持当前展示的工具 Tab 状态不变，规避 IndexedStack 越界崩溃
    if (widget.tabIndex < 12) {
      _currentToolIndex = widget.tabIndex;
      _initializedTabs.add(_currentToolIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = List.generate(12, (index) {
      if (!_initializedTabs.contains(index)) {
        return const SizedBox.shrink();
      }
      return switch (index) {
        0 => _OverviewTab(device: widget.device),
        1 => _ToolTabScrollView(
          child: _ControlTab(device: widget.device, sessions: widget.sessions),
        ),
        2 => _AppsTab(device: widget.device),
        3 => _FilesTab(device: widget.device),
        4 => _LogcatTab(device: widget.device),
        5 => Padding(
          padding: const EdgeInsets.all(16),
          child: TerminalTab(device: widget.device),
        ),
        6 => ProcessesTab(device: widget.device),
        7 => WebpagesTab(device: widget.device),
        8 => LayoutTab(device: widget.device),
        9 => _ScreenshotTab(device: widget.device),
        10 => PerformanceTab(
          device: widget.device,
          isVisible: _currentToolIndex == 10,
        ),
        11 => NetworkTab(device: widget.device),
        _ => const SizedBox.shrink(),
      };
    });

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: IndexedStack(index: _currentToolIndex, children: children),
    );
  }
}

/// Tab 内容统一使用内部滚动，避免外层页面滚动抢占桌面端滚轮事件。
class _ToolTabScrollView extends StatefulWidget {
  const _ToolTabScrollView({required this.child});

  final Widget child;

  @override
  State<_ToolTabScrollView> createState() => _ToolTabScrollViewState();
}

class _ToolTabScrollViewState extends State<_ToolTabScrollView> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _controller,
        primary: false,
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        child: widget.child,
      ),
    );
  }
}
