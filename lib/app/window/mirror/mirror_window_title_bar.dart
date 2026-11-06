part of 'mirror_window_app.dart';

/// 将标题栏回调连接到投屏 Controller，手势与加载态由独立组件管理。
extension _MirrorWindowTitleBar on _MirrorWindowContentState {
  Widget _buildTitleBar(
    BuildContext context, {
    required bool isIos,
    required bool isMirrorActive,
    required bool isAudioForwarded,
    required Color windowBackground,
  }) {
    final package = _controller.currentForegroundPackage;
    return MirrorWindowTitleBar(
      deviceName: widget.deviceName,
      backgroundColor: windowBackground,
      isIos: isIos,
      isAudioForwarded: isAudioForwarded,
      isMirrorActive: isMirrorActive,
      isAlwaysOnTop: _controller.isAlwaysOnTop,
      isFullScreen: _controller.isFullScreen,
      onTitleHoverChanged: (hovered) =>
          _refreshView(() => _isTitleHovered = hovered),
      foregroundAppAction: widget.startApp == null && package != null
          ? MirrorForegroundAppButton(
              deviceId: widget.deviceId,
              package: package,
              onOpen: () => _controller.openAppMirrorWindow(context),
              onQuickActions: () => showMirrorAppQuickActionsDialog(
                context: context,
                ref: ref,
                deviceId: widget.deviceId,
                package: package,
              ),
            )
          : null,
      onRetry: () {
        _whiteboard.clear();
        _controller.restartMirroring();
      },
      onToggleAlwaysOnTop: _controller.toggleAlwaysOnTop,
      onToggleFullScreen: () =>
          _controller.toggleFullScreen(context, !_controller.isFullScreen),
      onSettings: isIos
          ? null
          : () => showMirrorSettingsDialog(
              context: context,
              ref: ref,
              deviceId: widget.deviceId,
              windowId: widget.windowId,
              isAlwaysOnTop: _controller.isAlwaysOnTop,
            ),
    );
  }
}
