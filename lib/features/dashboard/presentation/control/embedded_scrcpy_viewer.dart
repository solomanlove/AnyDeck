import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrcpy_flutter/scrcpy_flutter.dart';

import '../../../../core/device_info/device_display_frame.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../../../core/scrcpy/scrcpy_keycode_helper.dart';
import 'embedded_scrcpy_geometry.dart';
import 'embedded_scrcpy_texture_surface.dart';

class EmbeddedScrcpyViewer extends ConsumerStatefulWidget {
  const EmbeddedScrcpyViewer({
    super.key,
    required this.deviceId,
    this.isFullScreen = false,
    this.onEscapePressed,
  });

  final String deviceId;
  final bool isFullScreen;
  final VoidCallback? onEscapePressed;

  @override
  ConsumerState<EmbeddedScrcpyViewer> createState() =>
      _EmbeddedScrcpyViewerState();
}

class _EmbeddedScrcpyViewerState extends ConsumerState<EmbeddedScrcpyViewer> {
  final GlobalKey _textureKey = GlobalKey();

  int? _videoWidth;
  int? _videoHeight;
  DeviceDisplayFrame? _displayFrame;
  int? _activeTextureId;
  Timer? _sizePollTimer;
  int _sizePollTick = 0;
  bool _isPollingSize = false;

  // Track pointers to ignore (e.g. right-click or middle-click)
  final Set<int> _ignoredPointers = {};

  // Track the last pan offset for trackpad scrolling
  Offset _lastPanOffset = Offset.zero;

  late final FocusNode _focusNode;
  late final TextEditingController _textController;

  /// 是否正在拦截 ESC 按键的抬起事件
  bool _interceptingEscape = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(
      debugLabel: 'embedded_scrcpy_viewer',
      onKeyEvent: (node, event) {
        return _handleKeyEvent(event);
      },
    );
    _textController = TextEditingController();
    _textController.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _sizePollTimer?.cancel();
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startSizePolling() {
    _sizePollTimer?.cancel();
    _sizePollTimer = Timer.periodic(const Duration(milliseconds: 250), (
      timer,
    ) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final isOnline = ref.read(deviceOnlineProvider(widget.deviceId));
      if (!isOnline) {
        timer.cancel();
        _sizePollTimer = null;
        return;
      }

      if (_isPollingSize) return;
      _isPollingSize = true;
      try {
        var changed = false;
        var videoSizeChanged = false;
        final size = await ScrcpyFlutter.getVideoSize(
          deviceId: widget.deviceId,
        );
        if (size != null && size['width']! > 0 && size['height']! > 0) {
          if (_videoWidth != size['width'] || _videoHeight != size['height']) {
            _videoWidth = size['width'];
            _videoHeight = size['height'];
            changed = true;
            videoSizeChanged = true;
          }
        }

        // 默认每 4 tick (即 1 秒) 轮询一次 displayFrame，但如果视频大小改变了则立即强制刷新
        if (videoSizeChanged || _sizePollTick % 4 == 0) {
          final displayFrame = await DeviceDisplayFrame.read(
            ref.read(adbServiceProvider),
            widget.deviceId,
          );
          if (displayFrame != null &&
              (_displayFrame?.width != displayFrame.width ||
                  _displayFrame?.height != displayFrame.height ||
                  _displayFrame?.rotation != displayFrame.rotation)) {
            _displayFrame = displayFrame;
            changed = true;
          }
        }

        _sizePollTick++;
        if (changed && mounted) {
          setState(() {});
        }
      } catch (e) {
        // Ignored
      } finally {
        _isPollingSize = false;
      }
    });
  }

  void _resetStreamGeometryIfNeeded(int? textureId) {
    if (_activeTextureId == textureId) return;
    _activeTextureId = textureId;
    _videoWidth = null;
    _videoHeight = null;
    _displayFrame = null;
    _sizePollTick = 0;
    _ignoredPointers.clear();

    _sizePollTimer?.cancel();
    _sizePollTimer = null;

    if (textureId != null) {
      _startSizePolling();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  List<int>? _mapPointerToVideo(PointerEvent event, String? resolution) {
    final renderBox =
        _textureKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;

    return ScrcpyVideoGeometry.mapPointerToVideo(
      event: event,
      renderBox: renderBox,
      resolution: resolution,
      videoWidth: _videoWidth,
      videoHeight: _videoHeight,
    );
  }

  Uint8List _serializeTouchEvent({
    required int action,
    required int pointerId,
    required int x,
    required int y,
    required int screenWidth,
    required int screenHeight,
    required int pressure,
    required int buttons,
  }) {
    final buffer = ByteData(32);
    buffer.setUint8(0, 2); // type = 2 (touch)
    buffer.setUint8(1, action);
    buffer.setUint64(2, pointerId, Endian.big);
    buffer.setUint32(10, x, Endian.big);
    buffer.setUint32(14, y, Endian.big);
    buffer.setUint16(18, screenWidth, Endian.big);
    buffer.setUint16(20, screenHeight, Endian.big);
    buffer.setUint16(22, pressure, Endian.big);
    buffer.setUint32(24, 0, Endian.big); // actionButton = 0
    buffer.setUint32(28, buttons, Endian.big);
    return buffer.buffer.asUint8List(0, 32);
  }

  int _floatToFixedPoint(double val) {
    if (val >= 1.0) return 32767;
    if (val <= -1.0) return -32768;
    return (val * (val < 0 ? 32768 : 32767)).toInt();
  }

  Uint8List _serializeScrollEvent({
    required int x,
    required int y,
    required int screenWidth,
    required int screenHeight,
    required double hScroll,
    required double vScroll,
  }) {
    final buffer = ByteData(21);
    buffer.setUint8(0, 3); // type = 3 (scroll)
    buffer.setUint32(1, x, Endian.big);
    buffer.setUint32(5, y, Endian.big);
    buffer.setUint16(9, screenWidth, Endian.big);
    buffer.setUint16(11, screenHeight, Endian.big);
    buffer.setInt16(13, _floatToFixedPoint(hScroll), Endian.big);
    buffer.setInt16(15, _floatToFixedPoint(vScroll), Endian.big);
    buffer.setUint32(17, 0, Endian.big); // buttons
    return buffer.buffer.asUint8List(0, 21);
  }

  void _sendTouchEvent(PointerEvent event, int action, String? resolution) {
    final mapped = _mapPointerToVideo(event, resolution);
    if (mapped == null) return;
    final x = mapped[0];
    final y = mapped[1];
    final realW = mapped[2];
    final realH = mapped[3];

    debugPrint(
      '[EmbeddedScrcpy] Touch: action=$action, x=$x, y=$y, realW=$realW, realH=$realH, resolution=$resolution, polledSize=${_videoWidth}x$_videoHeight',
    );

    final message = _serializeTouchEvent(
      action: action,
      pointerId: 0,
      x: x,
      y: y,
      screenWidth: realW,
      screenHeight: realH,
      pressure: event.pressure > 0 ? (event.pressure * 65535).toInt() : 65535,
      buttons: 0,
    );

    ScrcpyFlutter.sendControl(
      deviceId: widget.deviceId,
      controlMessage: message,
    ).then((success) {
      debugPrint('[EmbeddedScrcpy] sendControl Touch success = $success');
    });
  }

  void _sendScrollEvent(PointerScrollEvent event, String? resolution) {
    final mapped = _mapPointerToVideo(event, resolution);
    if (mapped == null) return;
    final x = mapped[0];
    final y = mapped[1];
    final realW = mapped[2];
    final realH = mapped[3];

    // In scrcpy scroll delta is normalized between -1.0 and 1.0.
    final hScroll = (event.scrollDelta.dx / 40.0).clamp(-1.0, 1.0);
    final vScroll = (-event.scrollDelta.dy / 40.0).clamp(
      -1.0,
      1.0,
    ); // Android scroll is inverted

    debugPrint(
      '[EmbeddedScrcpy] Scroll: x=$x, y=$y, realW=$realW, realH=$realH, hScroll=$hScroll, vScroll=$vScroll, polledSize=${_videoWidth}x$_videoHeight',
    );

    final message = _serializeScrollEvent(
      x: x,
      y: y,
      screenWidth: realW,
      screenHeight: realH,
      hScroll: hScroll,
      vScroll: vScroll,
    );

    ScrcpyFlutter.sendControl(
      deviceId: widget.deviceId,
      controlMessage: message,
    ).then((success) {
      debugPrint('[EmbeddedScrcpy] sendControl Scroll success = $success');
    });
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (_textController.value.composing.isValid) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    // 检查是否为 Command+V (Mac) 或 Control+V (其他 OS) 的粘贴快捷键
    final isV = key == LogicalKeyboardKey.keyV;
    final isPaste =
        isV &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed);

    if (isPaste) {
      if (event is KeyDownEvent) {
        Clipboard.getData(Clipboard.kTextPlain).then((clipboardData) {
          if (clipboardData != null &&
              clipboardData.text != null &&
              clipboardData.text!.isNotEmpty) {
            final text = clipboardData.text!;
            final message = ScrcpyKeycodeHelper.serializeTextEvent(text);
            ScrcpyFlutter.sendControl(
              deviceId: widget.deviceId,
              controlMessage: message,
            ).then((success) {
              debugPrint(
                '[EmbeddedScrcpy] Command/Control+V Paste Success: $success',
              );
            });
          }
        });
      }
      return KeyEventResult.handled;
    }

    // 如果按键为 ESC 且处于全屏，拦截所有事件（按下、抬起等）防止其发送给 Android 设备或导致状态不同步
    if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) {
        if (widget.isFullScreen) {
          _interceptingEscape = true;
          widget.onEscapePressed?.call();
          return KeyEventResult.handled;
        }
      } else if (event is KeyUpEvent) {
        if (_interceptingEscape) {
          _interceptingEscape = false;
          return KeyEventResult.handled;
        }
      }
    }

    int? action;
    if (event is KeyDownEvent) {
      action = 0;
    } else if (event is KeyUpEvent) {
      action = 1;
    } else if (event is KeyRepeatEvent) {
      action = 2;
    }

    if (action == null) return KeyEventResult.ignored;

    final androidKeycode = ScrcpyKeycodeHelper.getAndroidKeycode(key);

    if (androidKeycode != null) {
      final keyboard = HardwareKeyboard.instance;
      final hasModifiers =
          keyboard.isControlPressed ||
          keyboard.isAltPressed ||
          keyboard.isMetaPressed;

      if (ScrcpyKeycodeHelper.isControlKey(key) || hasModifiers) {
        final metaState = ScrcpyKeycodeHelper.getAndroidMetaState(event);
        final message = ScrcpyKeycodeHelper.serializeKeyCodeEvent(
          action: action,
          keycode: androidKeycode,
          repeat: action == 2 ? 1 : 0,
          metaState: metaState,
        );
        ScrcpyFlutter.sendControl(
          deviceId: widget.deviceId,
          controlMessage: message,
        ).then((success) {
          debugPrint(
            '[EmbeddedScrcpy] Sent keycode event: key=$key, action=$action, success=$success',
          );
        });
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _onTextChanged() {
    final value = _textController.value;
    if (value.composing.isValid) {
      return;
    }

    final text = value.text;
    if (text.isNotEmpty) {
      final message = ScrcpyKeycodeHelper.serializeTextEvent(text);
      ScrcpyFlutter.sendControl(
        deviceId: widget.deviceId,
        controlMessage: message,
      ).then((success) {
        debugPrint(
          '[EmbeddedScrcpy] Sent text event: text="$text", success=$success',
        );
      });
      _textController.value = TextEditingValue.empty;
    }
  }

  void _handlePointerDown(PointerDownEvent event, String? resolution) {
    _focusNode.requestFocus();
    if (event.buttons == kSecondaryMouseButton) {
      _ignoredPointers.add(event.pointer);
      ref
          .read(deviceActionServiceProvider)
          .keyEvent(widget.deviceId, 4); // KEYCODE_BACK
      debugPrint('[EmbeddedScrcpy] Intercepted right click -> Back');
      return;
    }
    if (event.buttons == kMiddleMouseButton) {
      _ignoredPointers.add(event.pointer);
      ref
          .read(deviceActionServiceProvider)
          .keyEvent(widget.deviceId, 3); // KEYCODE_HOME
      debugPrint('[EmbeddedScrcpy] Intercepted middle click -> Home');
      return;
    }
    _sendTouchEvent(event, 0, resolution); // DOWN
  }

  void _handlePointerMove(PointerMoveEvent event, String? resolution) {
    if (_ignoredPointers.contains(event.pointer)) {
      return;
    }
    _sendTouchEvent(event, 2, resolution); // MOVE
  }

  void _handlePointerUp(PointerUpEvent event, String? resolution) {
    if (_ignoredPointers.contains(event.pointer)) {
      _ignoredPointers.remove(event.pointer);
      return;
    }
    _sendTouchEvent(event, 1, resolution); // UP
  }

  void _handlePointerCancel(PointerCancelEvent event, String? resolution) {
    if (_ignoredPointers.contains(event.pointer)) {
      _ignoredPointers.remove(event.pointer);
      return;
    }
    _sendTouchEvent(event, 3, resolution); // CANCEL
  }

  void _handlePanZoomStart(PointerPanZoomStartEvent event) {
    _lastPanOffset = Offset.zero;
  }

  void _handlePanZoomUpdate(
    PointerPanZoomUpdateEvent event,
    String? resolution,
  ) {
    final delta = event.pan - _lastPanOffset;
    _lastPanOffset = event.pan;

    if (delta.dx == 0 && delta.dy == 0) return;

    final mapped = _mapPointerToVideo(event, resolution);
    if (mapped == null) return;
    final x = mapped[0];
    final y = mapped[1];
    final realW = mapped[2];
    final realH = mapped[3];

    // Scale delta similarly to scrollDelta
    final hScroll = (delta.dx / 40.0).clamp(-1.0, 1.0);
    final vScroll = (-delta.dy / 40.0).clamp(
      -1.0,
      1.0,
    ); // Android scroll is inverted

    debugPrint(
      '[EmbeddedScrcpy] PanScroll: x=$x, y=$y, realW=$realW, realH=$realH, hScroll=$hScroll, vScroll=$vScroll',
    );

    final message = _serializeScrollEvent(
      x: x,
      y: y,
      screenWidth: realW,
      screenHeight: realH,
      hScroll: hScroll,
      vScroll: vScroll,
    );

    ScrcpyFlutter.sendControl(
      deviceId: widget.deviceId,
      controlMessage: message,
    ).then((success) {
      debugPrint('[EmbeddedScrcpy] sendControl PanScroll success = $success');
    });
  }

  @override
  Widget build(BuildContext context) {
    final textureId = ref.watch(activeEmbeddedMirrorProvider(widget.deviceId));
    _resetStreamGeometryIfNeeded(textureId);
    final overviewAsync = ref.watch(deviceOverviewProvider(widget.deviceId));

    if (textureId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final resolution = overviewAsync.maybeWhen(
      data: (overview) => overview.physicalResolution,
      orElse: () => null,
    );
    final aspectRatio = ScrcpyVideoGeometry.resolveDisplayAwareAspectRatio(
      videoWidth: _videoWidth,
      videoHeight: _videoHeight,
      displayFrame: _displayFrame,
      fallbackResolution: resolution,
    );

    return Container(
      color: const Color(0xff121212),
      alignment: Alignment.center,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.0,
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  autofocus: true,
                  maxLines: 1,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                  ),
                  keyboardType: TextInputType.text,
                ),
              ),
            ),
          ),
          EmbeddedScrcpyTextureSurface(
            textureKey: _textureKey,
            textureId: textureId,
            aspectRatio: aspectRatio,
            onPointerDown: (e) => _handlePointerDown(e, resolution),
            onPointerMove: (e) => _handlePointerMove(e, resolution),
            onPointerUp: (e) => _handlePointerUp(e, resolution),
            onPointerCancel: (e) => _handlePointerCancel(e, resolution),
            onPointerPanZoomStart: _handlePanZoomStart,
            onPointerPanZoomUpdate: (e) => _handlePanZoomUpdate(e, resolution),
            onPointerSignal: (signal) {
              if (signal is PointerScrollEvent) {
                _sendScrollEvent(signal, resolution);
              }
            },
          ),
        ],
      ),
    );
  }
}
