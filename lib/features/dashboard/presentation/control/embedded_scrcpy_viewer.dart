import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrcpy_flutter/scrcpy_flutter.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/scrcpy/embedded_scrcpy_service.dart';

class EmbeddedScrcpyViewer extends ConsumerStatefulWidget {
  const EmbeddedScrcpyViewer({super.key, required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<EmbeddedScrcpyViewer> createState() => _EmbeddedScrcpyViewerState();
}

class _EmbeddedScrcpyViewerState extends ConsumerState<EmbeddedScrcpyViewer> {
  final GlobalKey _textureKey = GlobalKey();

  int? _videoWidth;
  int? _videoHeight;
  Timer? _sizePollTimer;

  @override
  void initState() {
    super.initState();
    _startSizePolling();
  }

  @override
  void dispose() {
    _sizePollTimer?.cancel();
    super.dispose();
  }

  void _startSizePolling() {
    _sizePollTimer?.cancel();
    _sizePollTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      try {
        final size = await ScrcpyFlutter.getVideoSize(deviceId: widget.deviceId);
        if (size != null && size['width']! > 0 && size['height']! > 0) {
          setState(() {
            _videoWidth = size['width'];
            _videoHeight = size['height'];
          });
          timer.cancel();
          debugPrint('[EmbeddedScrcpy] Polled video size successfully: ${_videoWidth}x$_videoHeight');
        }
      } catch (e) {
        // Ignored
      }
    });
  }

  double _getAspectRatio(String? resolutionStr) {
    if (resolutionStr == null || resolutionStr == '-') return 9 / 16;
    final match = RegExp(r'(\d+)\s*[xX]\s*(\d+)').firstMatch(resolutionStr);
    if (match != null) {
      final w = int.parse(match.group(1)!);
      final h = int.parse(match.group(2)!);
      if (w > 0 && h > 0) {
        return w / h;
      }
    }
    return 9 / 16;
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
    final renderBox = _textureKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localPosition = renderBox.globalToLocal(event.position);
    final size = renderBox.size;

    int realW = _videoWidth ?? size.width.toInt();
    int realH = _videoHeight ?? size.height.toInt();

    if (_videoWidth == null || _videoHeight == null) {
      if (resolution != null && resolution != '-') {
        final match = RegExp(r'(\d+)\s*[xX]\s*(\d+)').firstMatch(resolution);
        if (match != null) {
          final w = int.parse(match.group(1)!);
          final h = int.parse(match.group(2)!);
          if (w > 0 && h > 0) {
            realW = w;
            realH = h;
          }
        }
      }
    }

    final x = (localPosition.dx / size.width * realW).clamp(0.0, realW.toDouble()).toInt();
    final y = (localPosition.dy / size.height * realH).clamp(0.0, realH.toDouble()).toInt();

    debugPrint('[EmbeddedScrcpy] Touch: action=$action, x=$x, y=$y, realW=$realW, realH=$realH, resolution=$resolution, polledSize=${_videoWidth}x$_videoHeight');

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

    ScrcpyFlutter.sendControl(deviceId: widget.deviceId, controlMessage: message).then((success) {
      debugPrint('[EmbeddedScrcpy] sendControl Touch success = $success');
    });
  }

  void _sendScrollEvent(PointerScrollEvent event, String? resolution) {
    final renderBox = _textureKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localPosition = renderBox.globalToLocal(event.position);
    final size = renderBox.size;

    int realW = _videoWidth ?? size.width.toInt();
    int realH = _videoHeight ?? size.height.toInt();

    if (_videoWidth == null || _videoHeight == null) {
      if (resolution != null && resolution != '-') {
        final match = RegExp(r'(\d+)\s*[xX]\s*(\d+)').firstMatch(resolution);
        if (match != null) {
          final w = int.parse(match.group(1)!);
          final h = int.parse(match.group(2)!);
          if (w > 0 && h > 0) {
            realW = w;
            realH = h;
          }
        }
      }
    }

    final x = (localPosition.dx / size.width * realW).clamp(0.0, realW.toDouble()).toInt();
    final y = (localPosition.dy / size.height * realH).clamp(0.0, realH.toDouble()).toInt();

    // In scrcpy scroll delta is normalized between -1.0 and 1.0.
    final hScroll = (event.scrollDelta.dx / 40.0).clamp(-1.0, 1.0);
    final vScroll = (-event.scrollDelta.dy / 40.0).clamp(-1.0, 1.0); // Android scroll is inverted

    debugPrint('[EmbeddedScrcpy] Scroll: x=$x, y=$y, realW=$realW, realH=$realH, hScroll=$hScroll, vScroll=$vScroll, polledSize=${_videoWidth}x$_videoHeight');

    final message = _serializeScrollEvent(
      x: x,
      y: y,
      screenWidth: realW,
      screenHeight: realH,
      hScroll: hScroll,
      vScroll: vScroll,
    );

    ScrcpyFlutter.sendControl(deviceId: widget.deviceId, controlMessage: message).then((success) {
      debugPrint('[EmbeddedScrcpy] sendControl Scroll success = $success');
    });
  }

  @override
  Widget build(BuildContext context) {
    final textureId = ref.watch(activeEmbeddedMirrorProvider(widget.deviceId));
    final overviewAsync = ref.watch(deviceOverviewProvider(widget.deviceId));
    final actionService = ref.read(deviceActionServiceProvider);

    if (textureId == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final resolution = overviewAsync.maybeWhen(
      data: (overview) => overview.physicalResolution,
      orElse: () => null,
    );
    final aspectRatio = (_videoWidth != null && _videoHeight != null && _videoWidth! > 0 && _videoHeight! > 0)
        ? _videoWidth! / _videoHeight!
        : _getAspectRatio(resolution);

    return Container(
      color: const Color(0xff121212),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: Listener(
                  key: _textureKey,
                  onPointerDown: (e) => _sendTouchEvent(e, 0, resolution), // DOWN
                  onPointerMove: (e) => _sendTouchEvent(e, 2, resolution), // MOVE
                  onPointerUp: (e) => _sendTouchEvent(e, 1, resolution),   // UP
                  onPointerCancel: (e) => _sendTouchEvent(e, 3, resolution), // CANCEL
                  onPointerSignal: (signal) {
                    if (signal is PointerScrollEvent) {
                      _sendScrollEvent(signal, resolution);
                    }
                  },
                  child: Texture(textureId: textureId),
                ),
              ),
            ),
          ),
          // Navigation Keys toolbar
          Container(
            height: 48,
            color: const Color(0xff1e1e1e),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.chevron_left, color: Colors.white70),
                  onPressed: () => actionService.keyEvent(widget.deviceId, 4),
                ),
                IconButton(
                  tooltip: 'Home',
                  icon: const Icon(Icons.radio_button_unchecked, color: Colors.white70),
                  onPressed: () => actionService.keyEvent(widget.deviceId, 3),
                ),
                IconButton(
                  tooltip: 'Recents',
                  icon: const Icon(Icons.crop_square, color: Colors.white70),
                  onPressed: () => actionService.keyEvent(widget.deviceId, 187),
                ),
                IconButton(
                  tooltip: 'Power',
                  icon: const Icon(Icons.power_settings_new, color: Colors.white70),
                  onPressed: () => actionService.keyEvent(widget.deviceId, 26),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
