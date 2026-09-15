import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device_info/device_display_frame.dart';
import '../../core/providers/app_providers.dart';
import '../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../core/scrcpy/scrcpy_keycode_helper.dart';
import '../../app/settings/app_settings_controller.dart';
import 'embedded_scrcpy_geometry.dart';
import 'embedded_scrcpy_texture_surface.dart';
import '../../core/ios/ios_mirror_service.dart';
import '../../core/harmony/harmony_mirror_service.dart';
import 'ios_mirror_viewer.dart';

class EmbeddedScrcpyViewer extends ConsumerStatefulWidget {
  const EmbeddedScrcpyViewer({
    super.key,
    required this.deviceId,
    this.isFullScreen = false,
    this.onEscapePressed,
    this.isHarmony = false,
    this.onVideoSizeChanged,
  });

  final String deviceId;
  final bool isFullScreen;
  final VoidCallback? onEscapePressed;
  final bool isHarmony;
  final void Function(int width, int height)? onVideoSizeChanged;

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
  Timer? _autoPowerOffTimer;
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

  /// 判断当前设备是否为鸿蒙设备（支持 widget 显式传入、前缀匹配、投屏激活态或设备注册表）
  bool get _isHarmony =>
      widget.isHarmony ||
      widget.deviceId.startsWith('harmony:') ||
      ref.read(activeHarmonyMirrorProvider(widget.deviceId)) != null ||
      ref.read(harmonyMirrorServiceProvider).isActive(widget.deviceId) ||
      ref.read(deviceRegistryProvider).any(
        (d) => d.id == widget.deviceId && d.isHarmony,
      );

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
    _autoPowerOffTimer?.cancel();
    _sizePollTimer?.cancel();
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startAutoPowerOffTimer() {
    if (_autoPowerOffTimer?.isActive ?? false) {
      return;
    }
    stdout.writeln('[AutoPowerOff] Timer scheduled.');
    _autoPowerOffTimer = Timer(const Duration(seconds: 1), () async {
      if (!mounted) return;
      stdout.writeln('[AutoPowerOff] Timer triggered. toggling screen power off.');
      ref.read(screenPowerOffProvider(widget.deviceId).notifier).toggleScreenPower(true);
    });
  }

  void _startSizePolling() {
    _sizePollTimer?.cancel();
    _sizePollTimer = Timer.periodic(const Duration(milliseconds: 100), (
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
        var hasVideoSize = false;
        final size = _isHarmony
            ? ref.read(harmonyMirrorServiceProvider).getVideoSize(widget.deviceId)
            : ref.read(embeddedScrcpyServiceProvider).getVideoSize(widget.deviceId);
        if (size != null && size['width']! > 0 && size['height']! > 0) {
          hasVideoSize = true;
          if (_videoWidth != size['width'] || _videoHeight != size['height']) {
            _videoWidth = size['width'];
            _videoHeight = size['height'];
            debugPrint(
              '[EmbeddedScrcpy] Video size changed: '
              '${_videoWidth}x$_videoHeight texture=$_activeTextureId',
            );
            changed = true;
            widget.onVideoSizeChanged?.call(size['width']!, size['height']!);
          }
        }

        // 解码帧尺寸是渲染和触控的 source-of-truth；仅在首帧尚未到达且非鸿蒙设备时
        // 每秒读取一次 displayFrame 作为占位比例，避免持续执行 dumpsys display。
        if (!_isHarmony && !hasVideoSize && _sizePollTick % 10 == 0) {
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

  void _sendControlMessage(Uint8List message, {String? tag}) {
    final future = _isHarmony
        ? ref.read(harmonyMirrorServiceProvider).sendControl(
            deviceId: widget.deviceId,
            controlMessage: message,
          )
        : ref.read(embeddedScrcpyServiceProvider).sendControl(
            deviceId: widget.deviceId,
            controlMessage: message,
          );
    future.then((success) {
      if (tag != null) {
        debugPrint('[EmbeddedScrcpy] sendControl $tag success = $success');
      }
    });
  }

  void _sendTouchEvent(PointerEvent event, int action, String? resolution) {
    final mapped = _mapPointerToVideo(event, resolution);
    if (mapped == null) return;
    final x = mapped[0];
    final y = mapped[1];
    final realW = mapped[2];
    final realH = mapped[3];

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

    _sendControlMessage(message, tag: 'Touch');
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

    _sendControlMessage(message, tag: 'Scroll');
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
            _sendControlMessage(message, tag: 'Command/Control+V Paste');
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
        _sendControlMessage(message, tag: 'KeyCode');
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
      _sendControlMessage(message, tag: 'Text');
      _textController.value = TextEditingValue.empty;
    }
  }

  void _handlePointerDown(PointerDownEvent event, String? resolution) {
    _focusNode.requestFocus();

    final settings = ref.read(appSettingsProvider);
    stdout.writeln('[AutoPowerOff] Pointer down. autoPowerOffScreen=${settings.autoPowerOffScreen}, isScreenOff=${ref.read(screenPowerOffProvider(widget.deviceId))}');
    if (settings.autoPowerOffScreen) {
      final isScreenOff = ref.read(screenPowerOffProvider(widget.deviceId));
      if (!isScreenOff) {
        _startAutoPowerOffTimer();
      }
    }

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

    _sendControlMessage(message, tag: 'PanScroll');
  }

  @override
  Widget build(BuildContext context) {
    final registeredDevices = ref.watch(deviceRegistryProvider);
    final isIos = registeredDevices.any((d) => d.id == widget.deviceId && d.isIos) ||
        (widget.deviceId.length == 40 && !widget.deviceId.contains(RegExp(r'[^a-fA-F0-9]'))) ||
        (widget.deviceId.length == 25 && widget.deviceId.indexOf('-') == 8);

    if (isIos) {
      final port = ref.watch(activeIosMirrorProvider(widget.deviceId));
      if (port == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return IosMirrorViewer(
        deviceId: widget.deviceId,
        port: port,
      );
    }

    final isHarmony = widget.isHarmony ||
        widget.deviceId.startsWith('harmony:') ||
        ref.watch(activeHarmonyMirrorProvider(widget.deviceId)) != null ||
        registeredDevices.any((d) => d.id == widget.deviceId && d.isHarmony);

    final textureId = isHarmony
        ? ref.watch(activeHarmonyMirrorProvider(widget.deviceId))
        : ref.watch(activeEmbeddedMirrorProvider(widget.deviceId));
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
            key: ValueKey('$textureId:${_videoWidth}x$_videoHeight'),
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
