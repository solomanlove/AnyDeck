part of '../dashboard_screen.dart';

class _ScreenshotTab extends ConsumerStatefulWidget {
  const _ScreenshotTab({required this.device});

  final AdbDevice device;

  @override
  ConsumerState<_ScreenshotTab> createState() => _ScreenshotTabState();
}

class _ScreenshotTabState extends ConsumerState<_ScreenshotTab> with _ScreenRecordMixin {
  Uint8List? _screenshotBytes;
  bool _loading = false;
  String? _error;
  int _rotation = 0; // 0, 90, 180, 270
  bool _autoRefresh = false;
  Timer? _autoRefreshTimer;

  int _imgWidth = 0;
  int _imgHeight = 0;

  final TransformationController _transformationController = TransformationController();
  Size _viewportSize = const Size(400, 800);

  double get _fitScale {
    if (_screenshotBytes == null || _imgWidth <= 0 || _imgHeight <= 0) return 1.0;
    final rotatedW = (_rotation == 90 || _rotation == 270) ? _imgHeight : _imgWidth;
    final rotatedH = (_rotation == 90 || _rotation == 270) ? _imgWidth : _imgHeight;
    return min(
      _viewportSize.width / rotatedW,
      _viewportSize.height / rotatedH,
    );
  }

  double get _minScale {
    return min(max(0.01, _fitScale * 0.8), 1.0);
  }

  @override
  void initState() {
    super.initState();
    _capture();
  }

  @override
  void dispose() {
    _cleanupRecord();
    _autoRefreshTimer?.cancel();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ScreenshotTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id) {
      _autoRefreshTimer?.cancel();
      _autoRefresh = false;
      _screenshotBytes = null;
      _imgWidth = 0;
      _imgHeight = 0;
      _rotation = 0;
      _transformationController.value = Matrix4.identity();
      _capture();
    }
  }

  Future<void> _capture({bool isAuto = false}) async {
    if (_loading && !isAuto) return;
    setState(() {
      _loading = !isAuto; // Auto-refresh in the background without blocking the UI
      _error = null;
    });

    try {
      final bytes = await ref.read(adbServiceProvider).captureScreenshot(widget.device.id);
      if (mounted) {
        setState(() {
          _screenshotBytes = bytes;
          _loading = false;
          if (bytes.length > 24) {
            _imgWidth = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
            _imgHeight = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
          }
        });
        if (!isAuto) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _zoomReset();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
          if (isAuto) {
            _autoRefresh = false;
            _autoRefreshTimer?.cancel();
          }
        });
      }
    }
  }

  void _toggleAutoRefresh() {
    setState(() {
      _autoRefresh = !_autoRefresh;
      if (_autoRefresh) {
        _autoRefreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
          _capture(isAuto: true);
        });
      } else {
        _autoRefreshTimer?.cancel();
      }
    });
  }

  void _zoom(double factor) {
    final currentMatrix = _transformationController.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    final targetScale = currentScale * factor;
    if (targetScale < _minScale || targetScale > 10.0) return;

    final center = Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    final translation = currentMatrix.getTranslation();
    final newTx = center.dx * (1 - factor) + translation.x * factor;
    final newTy = center.dy * (1 - factor) + translation.y * factor;

    _transformationController.value = Matrix4.copy(currentMatrix)
      ..setTranslationRaw(newTx, newTy, 0.0)
      // ignore: deprecated_member_use
      ..scale(factor);
  }

  void _zoom1to1() {
    if (_screenshotBytes == null || _imgWidth <= 0 || _imgHeight <= 0) return;
    final rotatedW = (_rotation == 90 || _rotation == 270) ? _imgHeight : _imgWidth;
    final rotatedH = (_rotation == 90 || _rotation == 270) ? _imgWidth : _imgHeight;

    final offsetX = (_viewportSize.width - rotatedW) / 2;
    final offsetY = (_viewportSize.height - rotatedH) / 2;

    _transformationController.value = Matrix4.identity()
      ..setTranslationRaw(offsetX, offsetY, 0.0)
      // ignore: deprecated_member_use
      ..scale(1.0);
  }

  void _zoomReset() {
    if (_screenshotBytes == null || _imgWidth <= 0 || _imgHeight <= 0) return;
    final rotatedW = (_rotation == 90 || _rotation == 270) ? _imgHeight : _imgWidth;
    final rotatedH = (_rotation == 90 || _rotation == 270) ? _imgWidth : _imgHeight;

    final scale = min(
      _viewportSize.width / rotatedW,
      _viewportSize.height / rotatedH,
    );
    final renderedW = rotatedW * scale;
    final renderedH = rotatedH * scale;
    final offsetX = (_viewportSize.width - renderedW) / 2;
    final offsetY = (_viewportSize.height - renderedH) / 2;

    _transformationController.value = Matrix4.identity()
      ..setTranslationRaw(offsetX, offsetY, 0.0)
      // ignore: deprecated_member_use
      ..scale(scale);
  }

  Future<void> _saveScreenshot() async {
    if (_screenshotBytes == null) return;
    try {
      final location = await getSaveLocation(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'PNG Image', extensions: ['png']),
        ],
        suggestedName: 'screenshot_${widget.device.id}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      if (location == null) return;

      final file = File(location.path);
      await file.writeAsBytes(_screenshotBytes!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10n.t('saveSuccess')}: ${location.path}'),
            backgroundColor: const Color(0xff09c47c),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10n.t('error')}: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _copyScreenshot() async {
    if (_screenshotBytes == null) return;
    final success = await _copyImageToClipboard(_screenshotBytes!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? context.l10n.t('copySuccess') : '复制到剪贴板失败'),
          backgroundColor: success ? const Color(0xff09c47c) : Colors.red,
          behavior: SnackBarBehavior.floating,
          width: 300,
        ),
      );
    }
  }

  Future<bool> _copyImageToClipboard(Uint8List bytes) async {
    try {
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/adb_screenshot_temp.png');
      await tempFile.writeAsBytes(bytes);

      if (Platform.isMacOS) {
        final result = await Process.run('osascript', [
          '-e',
          'set the clipboard to (read (POSIX file "${tempFile.path}") as «class PNGf»)',
        ]);
        return result.exitCode == 0;
      } else if (Platform.isWindows) {
        final psCommand = 'Add-Type -AssemblyName System.Windows.Forms, System.Drawing; '
            '[System.Windows.Forms.Clipboard]::SetImage([System.Drawing.Image]::FromFile("${tempFile.path}"))';
        final result = await Process.run('powershell', ['-Command', psCommand]);
        return result.exitCode == 0;
      } else if (Platform.isLinux) {
        final result = await Process.run('xclip', [
          '-selection',
          'clipboard',
          '-t',
          'image/png',
          '-i',
          tempFile.path,
        ]);
        return result.exitCode == 0;
      }
      return false;
    } catch (e) {
      debugPrint('Failed to copy clipboard: $e');
      return false;
    }
  }

  String get _sizeLabel {
    if (_screenshotBytes == null) return '';
    final bytes = _screenshotBytes!.length;
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}MB';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _screenshotBytes == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _screenshotBytes == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _capture(),
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.t('refresh')),
            ),
          ],
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // 顶部控制工具栏
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              IconButton(
                tooltip: context.l10n.t('refresh'),
                icon: const Icon(Icons.refresh),
                onPressed: (_loading || isRecording) ? null : () => _capture(),
              ),
              IconButton(
                tooltip: context.l10n.t('save'),
                icon: const Icon(Icons.save_alt),
                onPressed: (_screenshotBytes == null || isRecording) ? null : _saveScreenshot,
              ),
              IconButton(
                tooltip: context.l10n.t('copy'),
                icon: const Icon(Icons.content_copy),
                onPressed: (_screenshotBytes == null || isRecording) ? null : _copyScreenshot,
              ),
              const VerticalDivider(width: 24, indent: 12, endIndent: 12),
              IconButton(
                tooltip: context.l10n.t('rotateLeft'),
                icon: const Icon(Icons.rotate_left),
                onPressed: (_screenshotBytes == null || isRecording) ? null : () {
                  setState(() {
                    _rotation = (_rotation - 90 + 360) % 360;
                    _zoomReset();
                  });
                },
              ),
              IconButton(
                tooltip: context.l10n.t('rotateRight'),
                icon: const Icon(Icons.rotate_right),
                onPressed: (_screenshotBytes == null || isRecording) ? null : () {
                  setState(() {
                    _rotation = (_rotation + 90) % 360;
                    _zoomReset();
                  });
                },
              ),
              const VerticalDivider(width: 24, indent: 12, endIndent: 12),
              IconButton(
                tooltip: context.l10n.t('zoomIn'),
                icon: const Icon(Icons.zoom_in),
                onPressed: (_screenshotBytes == null || isRecording) ? null : () => _zoom(1.2),
              ),
              IconButton(
                tooltip: context.l10n.t('zoomOut'),
                icon: const Icon(Icons.zoom_out),
                onPressed: (_screenshotBytes == null || isRecording) ? null : () => _zoom(0.8),
              ),
              IconButton(
                tooltip: context.l10n.t('zoomReset'),
                icon: const Icon(Icons.aspect_ratio),
                onPressed: (_screenshotBytes == null || isRecording) ? null : _zoomReset,
              ),
              IconButton(
                tooltip: context.l10n.t('zoom1to1'),
                icon: const Icon(Icons.fullscreen),
                onPressed: (_screenshotBytes == null || isRecording) ? null : _zoom1to1,
              ),
              const VerticalDivider(width: 24, indent: 12, endIndent: 12),
              IconButton(
                tooltip: context.l10n.t('autoRefresh'),
                icon: Icon(
                  Icons.history,
                  color: _autoRefresh ? colorScheme.primary : null,
                ),
                onPressed: (_screenshotBytes == null || isRecording) ? null : _toggleAutoRefresh,
              ),
              const VerticalDivider(width: 24, indent: 12, endIndent: 12),
              IconButton(
                tooltip: isRecording ? context.l10n.t('stopRecord') : context.l10n.t('startRecord'),
                icon: Icon(
                  isRecording ? Icons.stop : Icons.videocam,
                  color: isRecording ? Colors.red : null,
                ),
                onPressed: _loading
                    ? null
                    : (isRecording ? _stopRecording : _startRecording),
              ),
              if (isRecording) ...[
                const SizedBox(width: 8),
                const _PulsingRecordDot(),
                const SizedBox(width: 6),
                Text(
                  _formatDuration(recordDuration),
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const Spacer(),
              if (_screenshotBytes != null)
                Text(
                  '${_imgWidth}x$_imgHeight PNG $_sizeLabel',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        // 截图显示区域
        Expanded(
          child: Container(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final currentSize = Size(constraints.maxWidth, constraints.maxHeight);
                      if (_viewportSize != currentSize) {
                        _viewportSize = currentSize;
                        if (_screenshotBytes != null) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _zoomReset();
                          });
                        }
                      }

                      if (_screenshotBytes == null) {
                        return const SizedBox.shrink();
                      }

                      final rotatedW = (_rotation == 90 || _rotation == 270) ? _imgHeight.toDouble() : _imgWidth.toDouble();
                      final rotatedH = (_rotation == 90 || _rotation == 270) ? _imgWidth.toDouble() : _imgHeight.toDouble();

                      final minScaleVal = _minScale;
                      final marginX = max(400.0, (currentSize.width / minScaleVal - rotatedW) / 2);
                      final marginY = max(400.0, (currentSize.height / minScaleVal - rotatedH) / 2);

                      return InteractiveViewer(
                        transformationController: _transformationController,
                        boundaryMargin: EdgeInsets.symmetric(
                          horizontal: marginX,
                          vertical: marginY,
                        ),
                        minScale: minScaleVal,
                        maxScale: 10.0,
                        constrained: false,
                        child: SizedBox(
                          width: rotatedW,
                          height: rotatedH,
                          child: Center(
                            child: RotatedBox(
                              quarterTurns: _rotation ~/ 90,
                              child: Image.memory(
                                _screenshotBytes!,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_loading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.3),
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
