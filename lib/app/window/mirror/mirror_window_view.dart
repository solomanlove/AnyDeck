part of 'mirror_window_app.dart';

/// 投屏窗口内容组合；快捷键范围覆盖画面、标题栏和自动隐藏工具栏。
extension _MirrorWindowView on _MirrorWindowContentState {
  Widget _buildWindow(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final airplayHandle = _airplayHandle;
    if (airplayHandle != null) {
      return IosAirPlayMirrorContent(
        handle: airplayHandle,
        deviceName: widget.deviceName,
        initialAspectRatio: _airplayAspectRatio,
        autoHideControls:
            !settings.mirrorControlsAlwaysVisible && !_whiteboardMode,
        isAlwaysOnTop: _controller.isAlwaysOnTop,
        onToggleAlwaysOnTop: _controller.toggleAlwaysOnTop,
        isFullScreen: _controller.isFullScreen,
        onToggleFullScreen: () =>
            _controller.toggleFullScreen(context, !_controller.isFullScreen),
        toolbar: MirrorFloatingToolbar(
          deviceId: widget.deviceId,
          deviceName: widget.deviceName,
          windowId: widget.windowId,
          controller: _controller,
          isAirplay: true,
          airplayHandle: airplayHandle,
          whiteboard: _whiteboard,
        ),
        whiteboard: _whiteboard,
        onDisconnected: () {
          if (!mounted ||
              ref.read(activeIosMirrorProvider(widget.deviceId)) == null) {
            return;
          }
          _whiteboard.clear();
          _refreshView(() => _airplayHandle = null);
          unawaited(
            DesktopWindowTitleService.setTitle(
              '${widget.deviceName} · ${context.l10n.t('iosMirrorUsbNative')}',
            ),
          );
        },
      );
    }
    final sdkVersion =
        ref.watch(deviceSdkVersionProvider(widget.deviceId)) ?? 0;
    final isAudioForwarded =
        (sdkVersion >= 30) &&
        !_controller.isAudioMuted &&
        settings.mirrorAudioEnabled;

    // 监听设备在线状态，若设备断开则强制停止投屏
    ref.listen<bool>(deviceOnlineProvider(widget.deviceId), (previous, next) {
      if (!next) {
        _controller.forceStopMirroring();
      }
    });

    // 监听包列表加载状态，以同步最新的前台应用信息
    ref.listen<AsyncValue<List<AdbPackage>>>(
      packagesProvider(widget.deviceId),
      (previous, next) {
        if (next is AsyncData<List<AdbPackage>>) {
          _controller.updateForegroundPackageFromList(next.value);
        }
      },
    );

    // 监听全局设置中投屏窗口置顶的变化
    ref.listen<bool>(appSettingsProvider.select((s) => s.scrcpyAlwaysOnTop), (
      previous,
      next,
    ) {
      _controller.updateAlwaysOnTop(next);
    });

    final isIos =
        widget.isIos ||
        (widget.deviceId.length == 40 &&
            !widget.deviceId.contains(RegExp(r'[^a-fA-F0-9]'))) ||
        (widget.deviceId.length == 25 && widget.deviceId.indexOf('-') == 8);
    final isMirrorActive = isIos
        ? ref.watch(activeIosMirrorProvider(widget.deviceId)) != null
        : (widget.isHarmony
              ? ref.watch(activeHarmonyMirrorProvider(widget.deviceId)) != null
              : ref.watch(activeEmbeddedMirrorProvider(widget.deviceId)) !=
                    null);
    final isLiveMirrorVisible =
        isMirrorActive &&
        !_controller.isLoading &&
        _controller.errorMessage == null;
    final windowBackground = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xff121212)
        : const Color(0xfff8f9fa);
    // 根据控制器状态组装核心内容区域
    Widget contentWidget;
    //加载中
    if (_controller.isLoading) {
      contentWidget = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              context.l10n.t('startingMirrorService'),
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      );
    }
    //加载出错了
    else if (_controller.errorMessage != null) {
      contentWidget = MirrorStatusView(
        rawErrorMessage: _controller.errorMessage,
        onRetry: () {
          _whiteboard.clear();
          _controller.restartMirroring();
        },
        onPrimaryMirror: widget.startApp == null
            ? null
            : () => _controller.openPrimaryMirrorWindow(context),
      );
    }
    //投屏正常
    else if (isMirrorActive) {
      contentWidget = ClipRRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            FusionResizeTransition(
              resizing: widget.startApp != null && _controller.isFusionResizing,
              child: Listener(
                key: _viewerKey,
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) {
                  if (_whiteboard.active) return;
                  final now = DateTime.now();
                  // 判定双击
                  if (_lastPointerDownTime != null &&
                      now.difference(_lastPointerDownTime!) <
                          const Duration(milliseconds: 300)) {
                    _controller.handleDoubleTap(context, e);
                  }
                  _lastPointerDownTime = now;
                  // 只有开启了自动识别设置，点击手机画面时才触发自动防抖识别
                  if (settings.autoIdentifyForegroundApp) {
                    _controller.triggerIdentifyForegroundApp();
                  }
                },
                child: EmbeddedScrcpyViewer(
                  deviceId: widget.deviceId,
                  whiteboard: _whiteboard,
                  isHarmony: widget.isHarmony,
                  isFullScreen: _controller.isFullScreen,
                  onVideoSizeChanged: (width, height) {
                    _whiteboard.updateVideoOrientation(width, height);
                    _controller.onVideoSizeChanged(width, height);
                  },
                  onIosVideoGeometryChanged: (width, height, viewport) {
                    _whiteboard.updateVideoOrientation(width, height);
                    _controller.onIosVideoGeometryChanged(
                      width,
                      height,
                      viewport,
                    );
                  },
                  onEscapePressed: () {
                    if (_controller.isFullScreen) {
                      _controller.toggleFullScreen(context, false);
                    }
                  },
                ),
              ),
            ),
            if (_appTaskMonitor != null)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _appTaskMonitor!,
                  builder: (context, child) {
                    final monitor = _appTaskMonitor!;
                    if (!monitor.isAway) return const SizedBox.shrink();
                    final app = ref
                        .read(packageMetadataResolverProvider)
                        .resolve(
                          AdbPackage(
                            name: widget.startApp!,
                            label: widget.deviceName,
                          ),
                          preferredDeviceId: widget.deviceId,
                        );
                    return FusionAppOnPhonePlaceholder(
                      appName: app.displayName,
                      iconPath: app.iconLocalPath,
                      isRestarting: monitor.isRestarting,
                      onRestart: _restartFusionApp,
                    );
                  },
                ),
              ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Align(
                alignment: Alignment.topLeft,
                child: IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: _isTitleHovered && !_controller.isFullScreen
                        ? MirrorDeviceInfoOverlay(
                            deviceId: widget.deviceId,
                            deviceName: widget.deviceName,
                            transport: isIos || widget.isHarmony
                                ? null
                                : MirrorTransportType.fromDeviceId(
                                    widget.deviceId,
                                  ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    //停止投屏或者设备断开
    else {
      contentWidget = MirrorStatusView(
        isStoppedState: true,
        onRetry: _controller.restartMirroring,
      );
    }

    return Scaffold(
      backgroundColor: isLiveMirrorVisible
          ? Colors.transparent
          : windowBackground,
      body: DragDropTargetOverlay(
        // 支持将 APK 或普通文件拖拽入投屏窗口进行安装/上传
        onDragDone: (files) => _controller.handleDrop(context, files),
        child: KeyboardListener(
          focusNode: _keyboardFocusNode,
          onKeyEvent: (event) {
            // 全屏状态下按 ESC 退出全屏
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              if (_controller.isFullScreen) {
                _controller.toggleFullScreen(context, false);
              }
            }
          },
          child: MirrorImmersiveOverlay(
            autoHide:
                isLiveMirrorVisible &&
                !settings.mirrorControlsAlwaysVisible &&
                !_whiteboardMode,
            viewer: contentWidget,
            titleBar: _buildTitleBar(
              context,
              isIos: isIos,
              isMirrorActive: isMirrorActive,
              isAudioForwarded: isAudioForwarded,
              windowBackground: windowBackground,
            ),
            toolbar: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Expanded(
                    child: MirrorFloatingToolbar(
                      deviceId: widget.deviceId,
                      deviceName: widget.deviceName,
                      windowId: widget.windowId,
                      controller: _controller,
                      whiteboard: _whiteboard,
                    ),
                  ),
                  MirrorSessionFps(
                    deviceId: widget.deviceId,
                    isIos: isIos,
                    isHarmony: widget.isHarmony,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
