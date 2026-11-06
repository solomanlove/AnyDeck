part of 'mirror_window_app.dart';

/// 投屏标题栏的窗口操作与快捷键绑定，与画面和会话生命周期分离。
extension _MirrorWindowTitleBar on _MirrorWindowContentState {
  Widget _buildTitleBar(
    BuildContext context, {
    required bool isIos,
    required bool isMirrorActive,
    required bool isAudioForwarded,
    required Color windowBackground,
  }) {
    return DragToMoveArea(
      child: Container(
        height: 30,
        padding: EdgeInsets.only(left: Platform.isMacOS ? 80 : 16, right: 4),
        decoration: BoxDecoration(
          color: windowBackground,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: MouseRegion(
                      onEnter: (_) =>
                          _refreshView(() => _isTitleHovered = true),
                      onExit: (_) =>
                          _refreshView(() => _isTitleHovered = false),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: isIos
                                  ? '${widget.deviceName} · ${context.l10n.t('iosMirrorUsbNative')}'
                                  : widget.deviceName,
                              style: Theme.of(
                                context,
                              ).textTheme.headlineSmall?.copyWith(fontSize: 16),
                            ),
                            if (isAudioForwarded)
                              WidgetSpan(
                                alignment: PlaceholderAlignment.top,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Tooltip(
                                    message: context.l10n.t(
                                      'audioForwardingTooltip',
                                    ),
                                    child: Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (widget.startApp == null &&
                      _controller.currentForegroundPackage != null) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: _appMirrorTooltip(context),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) =>
                            _refreshView(() => _isIconHovered = true),
                        onExit: (_) =>
                            _refreshView(() => _isIconHovered = false),
                        child: AnimatedScale(
                          scale: _isIconHovered ? 1.2 : 1.0,
                          duration: const Duration(milliseconds: 100),
                          child: GestureDetector(
                            onTap: () =>
                                _controller.openAppMirrorWindow(context),
                            onLongPress: () {
                              if (_controller.currentForegroundPackage !=
                                  null) {
                                showMirrorAppQuickActionsDialog(
                                  context: context,
                                  ref: ref,
                                  deviceId: widget.deviceId,
                                  package:
                                      _controller.currentForegroundPackage!,
                                );
                              }
                            },
                            onSecondaryTap: () {
                              if (_controller.currentForegroundPackage !=
                                  null) {
                                showMirrorAppQuickActionsDialog(
                                  context: context,
                                  ref: ref,
                                  deviceId: widget.deviceId,
                                  package:
                                      _controller.currentForegroundPackage!,
                                );
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _isIconHovered
                                      ? Colors.orange.withValues(alpha: 0.8)
                                      : Colors.transparent,
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child:
                                    (_controller
                                                .currentForegroundPackage!
                                                .iconLocalPath !=
                                            null &&
                                        File(
                                          _controller
                                              .currentForegroundPackage!
                                              .iconLocalPath!,
                                        ).existsSync())
                                    ? Image.file(
                                        File(
                                          _controller
                                              .currentForegroundPackage!
                                              .iconLocalPath!,
                                        ),
                                        width: 18,
                                        height: 18,
                                        fit: BoxFit.contain,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Icon(
                                                  CupertinoIcons.app,
                                                  size: 16,
                                                  color: Theme.of(
                                                    context,
                                                  ).appColors.toolbarForeground,
                                                ),
                                      )
                                    : Icon(
                                        CupertinoIcons.app,
                                        size: 16,
                                        color: Theme.of(
                                          context,
                                        ).appColors.toolbarForeground,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isMirrorActive) const MirrorSessionDuration(),
            // 重新连接/刷新按钮
            MirrorToolbarButton(
              icon: Icon(
                CupertinoIcons.refresh,
                color: Theme.of(context).appColors.toolbarForeground,
                size: 16,
              ),
              tooltip: context.l10n.t('retry'),
              shortcut: MirrorShortcut.reconnect,
              onPressed: () {
                _whiteboard.clear();
                _controller.restartMirroring();
              },
            ),
            // 窗口置顶按钮
            MirrorToolbarButton(
              icon: Icon(
                _controller.isAlwaysOnTop
                    ? CupertinoIcons.pin_fill
                    : CupertinoIcons.pin,
                color: _controller.isAlwaysOnTop
                    ? Colors.orange
                    : (Theme.of(context).appColors.toolbarForeground),
              ),
              tooltip: _controller.isAlwaysOnTop
                  ? context.l10n.t('unpinAlwaysOnTop')
                  : context.l10n.t('pinAlwaysOnTop'),
              shortcut: MirrorShortcut.alwaysOnTop,
              onPressed: _controller.toggleAlwaysOnTop,
            ),
            // 窗口全屏按钮
            MirrorToolbarButton(
              icon: Icon(
                _controller.isFullScreen
                    ? CupertinoIcons.fullscreen_exit
                    : CupertinoIcons.fullscreen,
                color: Theme.of(context).appColors.toolbarForeground,
              ),
              tooltip: _controller.isFullScreen
                  ? context.l10n.t('exitFullScreen')
                  : context.l10n.t('enterFullScreen'),
              shortcut: MirrorShortcut.fullScreen,
              onPressed: () => _controller.toggleFullScreen(
                context,
                !_controller.isFullScreen,
              ),
            ),
            // 投屏高级设置按钮
            if (!isIos)
              MirrorToolbarButton(
                icon: Icon(
                  CupertinoIcons.settings,
                  color: Theme.of(context).appColors.toolbarForeground,
                ),
                tooltip: context.l10n.t('mirrorQualitySettings'),
                shortcut: MirrorShortcut.mirrorSettings,
                onPressed: () => showMirrorSettingsDialog(
                  context: context,
                  ref: ref,
                  deviceId: widget.deviceId,
                  windowId: widget.windowId,
                  isAlwaysOnTop: _controller.isAlwaysOnTop,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
