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

        return DropTarget(
          onDragDone: (details) =>
              _handleDrop(context, ref, device, details.files),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SelectedDeviceHeader(device: device),
              const SizedBox(height: 16),
              if (hasBoundedHeight)
                Expanded(
                  child: _ToolContentCard(
                    device: device,
                    sessions: sessions,
                    tabIndex: tabIndex,
                  ),
                )
              else
                SizedBox(
                  height: 800,
                  child: _ToolContentCard(
                    device: device,
                    sessions: sessions,
                    tabIndex: tabIndex,
                  ),
                ),
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
    final appService = ref.read(appManagementServiceProvider);
    final fileService = ref.read(fileManagerServiceProvider);
    final remotePath = ref.read(remotePathProvider);

    for (final file in files) {
      final isApk = file.path.toLowerCase().endsWith('.apk');
      final result = isApk
          ? await appService.installApk(device.id, file.path)
          : await fileService.push(device.id, file.path, remotePath);
      if (!context.mounted) {
        return;
      }
      _showSnack(
        context,
        '${file.name}: ${result.message}',
        isError: !result.isSuccess,
      );
    }
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

  @override
  void initState() {
    super.initState();
    _initializedTabs.add(widget.tabIndex);
  }

  @override
  void didUpdateWidget(covariant _ToolContentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果设备切换了，清空已初始化的 Tab 状态，释放资源
    if (oldWidget.device.id != widget.device.id) {
      _initializedTabs.clear();
    }
    _initializedTabs.add(widget.tabIndex);
  }

  @override
  Widget build(BuildContext context) {
    final children = List.generate(12, (index) {
      if (!_initializedTabs.contains(index)) {
        return const SizedBox.shrink();
      }
      return switch (index) {
        0 => _ToolTabScrollView(child: _OverviewTab(device: widget.device)),
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
        10 => PerformanceTab(device: widget.device),
        11 => NetworkTab(device: widget.device),
        _ => const SizedBox.shrink(),
      };
    });

    return Card(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: IndexedStack(
          index: widget.tabIndex,
          children: children,
        ),
      ),
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

/// 概览 tab，只承载选中设备的只读手机信息。
