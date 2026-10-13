import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../multi_window_compat.dart';

/// 将控制区放在视频区域外；隐藏时保留固定外框槽位，避免手机画面缩放或位移。
class MirrorImmersiveOverlay extends StatefulWidget {
  const MirrorImmersiveOverlay({
    super.key,
    required this.viewer,
    required this.titleBar,
    required this.toolbar,
    this.controlsEnabled = true,
    this.autoHide = true,
  });

  final Widget viewer;
  final Widget titleBar;
  final Widget toolbar;
  final bool controlsEnabled;
  final bool autoHide;

  @override
  State<MirrorImmersiveOverlay> createState() => _MirrorImmersiveOverlayState();
}

class _MirrorImmersiveOverlayState extends State<MirrorImmersiveOverlay> {
  static const _windowChannel = MethodChannel('any_deck/window');
  static const _hideDelay = Duration(milliseconds: 1500);
  static const _viewerHideDelay = Duration(milliseconds: 300);
  static const _sideControlsWidth = mirrorWindowSideChromeWidth;
  static const _animationDuration = Duration(milliseconds: 160);

  Timer? _hideTimer;
  bool _controlsVisible = true;
  bool _pointerOverControls = false;
  bool _modalRouteVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncWindowButtonVisibility(_controlsVisible));
    });
    _scheduleHide();
  }

  @override
  void didUpdateWidget(covariant MirrorImmersiveOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.controlsEnabled) {
      _hideTimer?.cancel();
      _setControlsVisible(false);
    } else if (!oldWidget.controlsEnabled || !widget.autoHide) {
      _showAndScheduleHide();
    } else if (!oldWidget.autoHide && widget.autoHide) {
      _scheduleHide();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final modalRouteVisible = !(ModalRoute.of(context)?.isCurrent ?? true);
    if (_modalRouteVisible == modalRouteVisible) return;
    _modalRouteVisible = modalRouteVisible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_modalRouteVisible) {
        _hideTimer?.cancel();
        _setControlsVisible(true);
      } else {
        _showAndScheduleHide();
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _showAndScheduleHide() {
    if (!widget.controlsEnabled) return;
    _setControlsVisible(true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.controlsEnabled ||
        !widget.autoHide ||
        _pointerOverControls ||
        _modalRouteVisible) {
      return;
    }
    _hideTimer = Timer(_hideDelay, () {
      if (mounted && !_pointerOverControls && !_modalRouteVisible) {
        _setControlsVisible(false);
      }
    });
  }

  void _scheduleViewerHide() {
    _hideTimer?.cancel();
    if (!widget.controlsEnabled ||
        !widget.autoHide ||
        _pointerOverControls ||
        _modalRouteVisible) {
      return;
    }
    _hideTimer = Timer(_viewerHideDelay, () {
      if (mounted && !_pointerOverControls && !_modalRouteVisible) {
        _setControlsVisible(false);
      }
    });
  }

  void _setPointerOverControls(bool value) {
    _pointerOverControls = value;
    if (value) {
      _hideTimer?.cancel();
      _setControlsVisible(true);
    } else {
      _scheduleHide();
    }
  }

  void _setControlsVisible(bool visible) {
    if (!mounted || _controlsVisible == visible) return;
    setState(() => _controlsVisible = visible);
    unawaited(_syncWindowButtonVisibility(visible));
  }

  Future<void> _syncWindowButtonVisibility(bool visible) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      await _windowChannel.invokeMethod<void>(
        'setWindowButtonVisibility',
        visible,
      );
    } on MissingPluginException {
      // 测试环境或旧 Runner 没有原生窗口按钮通道时忽略。
    }
  }

  Widget _controlSlot(Widget child) {
    return MouseRegion(
      onEnter: (_) => _setPointerOverControls(true),
      onExit: (_) => _setPointerOverControls(false),
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1 : 0,
        duration: _animationDuration,
        child: IgnorePointer(
          ignoring: !_controlsVisible,
          child: child,
        ),
      ),
    );
  }

  Widget _viewerRegion() {
    return MouseRegion(
      onEnter: (_) => _scheduleViewerHide(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          _hideTimer?.cancel();
          if (widget.autoHide && !_modalRouteVisible) {
            _setControlsVisible(false);
          }
        },
        child: widget.viewer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final toolbarBackground = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xff121212)
        : const Color(0xfff8f9fa);
    return MouseRegion(
      onExit: (_) {
        _hideTimer?.cancel();
        if (widget.autoHide && !_modalRouteVisible && _controlsVisible) {
          _setControlsVisible(false);
        }
      },
      child: Column(
        children: [
          if (widget.controlsEnabled)
            SizedBox(height: 30, child: _controlSlot(widget.titleBar)),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _viewerRegion()),
                if (widget.controlsEnabled)
                  SizedBox(
                    width: _sideControlsWidth,
                    child: _controlSlot(DecoratedBox(
                      decoration: BoxDecoration(
                        color: toolbarBackground,
                        border: Border(
                          left: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                      child: SizedBox.expand(child: widget.toolbar),
                    )),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
