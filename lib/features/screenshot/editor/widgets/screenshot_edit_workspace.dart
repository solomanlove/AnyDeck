import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/l10n/app_localizations.dart';
import '../../model/screenshot_state.dart';
import '../../widgets/screenshot_bottom_bar.dart';
import '../../widgets/screenshot_canvas.dart';
import '../controller/screenshot_edit_controller.dart';
import '../model/screenshot_edit.dart';
import '../renderer/screenshot_edit_renderer.dart';
import 'screenshot_edit_overlay.dart';
import 'screenshot_edit_toolbar.dart';

/// 当前截图的独立编辑工作区，复用普通截图的缩放画布与底栏。
/// source 保留为提交身份标识，内部 clone 独立持有生命周期；
/// onDone 接管导出结果的 Image，onCancel 退出并保留进入前的画面。
class ScreenshotEditWorkspace extends ConsumerStatefulWidget {
  const ScreenshotEditWorkspace({
    super.key,
    required this.source,
    required this.screenshotState,
    required this.onDone,
    required this.onCancel,
    this.onAbandon,
  });

  final ui.Image source;
  final ScreenshotLayoutState screenshotState;
  final ValueChanged<ScreenshotEditResult> onDone;
  final VoidCallback onCancel;
  final VoidCallback? onAbandon;

  @override
  ConsumerState<ScreenshotEditWorkspace> createState() =>
      _ScreenshotEditWorkspaceState();
}

class _ScreenshotEditWorkspaceState
    extends ConsumerState<ScreenshotEditWorkspace> {
  final _transform = TransformationController();
  final _canvasKey = GlobalKey<ScreenshotCanvasState>();
  late final _sessionId = UniqueKey().toString();
  late final ui.Image _source;
  ui.Image? _mosaic;
  bool _preparing = true;
  bool _exporting = false;
  String? _error;

  bool get _busy => _preparing || _exporting;

  @override
  void initState() {
    super.initState();
    _source = widget.source.clone();
    _prepareMosaic();
  }

  Future<void> _prepareMosaic() async {
    setState(() {
      _preparing = true;
      _error = null;
    });
    final retainedSource = _source.clone();
    try {
      final image = await ScreenshotEditRenderer.createMosaic(retainedSource);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _mosaic = image);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      retainedSource.dispose();
      if (mounted) setState(() => _preparing = false);
    }
  }

  @override
  void dispose() {
    // Riverpod 不允许在 Widget 销毁中同步修改状态，稍后清理被移除的编辑会话。
    final onAbandon = widget.onAbandon;
    if (onAbandon != null) scheduleMicrotask(onAbandon);
    _source.dispose();
    _mosaic?.dispose();
    _transform.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    if (_exporting) return;
    final edit = ref.read(screenshotEditControllerProvider(_sessionId));
    if (edit.isDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.t('screenshotEditDiscardTitle')),
          content: Text(context.l10n.t('screenshotEditDiscardMessage')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.t('screenshotEditKeep')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.t('screenshotEditDiscard')),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    widget.onCancel();
  }

  Future<void> _done() async {
    if (_busy) return;
    final controller = ref.read(
      screenshotEditControllerProvider(_sessionId).notifier,
    );
    controller.end();
    final edit = ref.read(screenshotEditControllerProvider(_sessionId));
    if (edit.marks.isEmpty) {
      widget.onCancel();
      return;
    }
    setState(() {
      _exporting = true;
      _error = null;
    });
    // 跨异步边界独立持有句柄，设备切换销毁工作区后仍能安全释放结果。
    final retainedSource = _source.clone();
    final retainedMosaic = _mosaic?.clone();
    try {
      final result = await ScreenshotEditRenderer.render(
        retainedSource,
        edit.marks,
        mosaicImage: retainedMosaic,
      );
      if (!mounted) {
        result.image.dispose();
        return;
      }
      widget.onDone(result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      retainedSource.dispose();
      retainedMosaic?.dispose();
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = screenshotEditControllerProvider(_sessionId);
    final tool = ref.watch(provider.select((state) => state.tool));
    final controller = ref.read(provider.notifier);
    final screenshot = widget.screenshotState;
    return Column(
      children: [
        Consumer(
          builder: (context, ref, _) => ScreenshotEditToolbar(
            state: ref.watch(provider),
            busy: _busy,
            mosaicAvailable: _mosaic != null,
            onToolChanged: controller.selectTool,
            onColorChanged: controller.setColor,
            onWidthChanged: controller.setWidth,
            onUndo: controller.undo,
            onRedo: controller.redo,
            onClear: controller.clear,
            onCancel: _cancel,
            onDone: _done,
          ),
        ),
        if (_error != null)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n
                          .t(
                            _mosaic == null
                                ? 'screenshotEditPrepareFailed'
                                : 'screenshotEditExportFailed',
                          )
                          .replaceAll('{error}', _error!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  if (_mosaic == null)
                    TextButton(
                      onPressed: _preparing ? null : _prepareMosaic,
                      child: Text(context.l10n.t('screenshotEditRetry')),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: ScreenshotCanvas(
            key: _canvasKey,
            decodedImage: _source,
            rotationAngle: screenshot.rotation,
            transformationController: _transform,
            isLayoutAnalysis: false,
            panEnabled: !_busy && tool == ScreenshotEditTool.pan,
            isLoading: _busy,
            imageOverlay: ScreenshotEditOverlay(
              sessionId: _sessionId,
              source: _source,
              mosaicImage: _mosaic,
              rotation: screenshot.rotation,
              busy: _busy,
            ),
          ),
        ),
        IgnorePointer(
          ignoring: _busy,
          child: ScreenshotBottomBar(
            state: screenshot,
            onZoomIn: () => _canvasKey.currentState?.zoom(1.2),
            onZoomOut: () => _canvasKey.currentState?.zoom(0.8),
            onZoom1To1: () => _canvasKey.currentState?.zoom1to1(),
            onZoomReset: () => _canvasKey.currentState?.resetZoomAndPan(),
          ),
        ),
      ],
    );
  }
}
