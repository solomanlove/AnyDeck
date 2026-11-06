import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor/model/screenshot_edit.dart';
import '../model/screenshot_state.dart';

/// 截图会话中的编辑结果所有权与设备操作互斥，避免污染布局树和原始 PNG。
mixin ScreenshotEditSession on Notifier<ScreenshotLayoutState> {
  ui.Image? _editedImage;

  void pauseAutoRefreshForTabSwitch();
  void invalidateCaptureForEditing();

  /// 暂停连续截图并使已发出的自动截图失效，冻结当前画面。
  void beginEditing() {
    if (!state.hasImage ||
        state.isLoading ||
        state.isRecordingActive ||
        state.isEditing ||
        state.displayImage == null) {
      return;
    }
    pauseAutoRefreshForTabSwitch();
    invalidateCaptureForEditing();
    state = state.copyWith(isEditing: true, isAutoRefresh: false);
  }

  void cancelEditing() {
    if (!ref.mounted || !state.isEditing) return;
    state = state.copyWith(isEditing: false);
  }

  /// 隐藏工作区切设备/路由被移除时，清理没有 UI 再持有的临时编辑状态。
  void abandonEditing(ui.Image source) {
    if (ref.mounted && state.displayImage == source) cancelEditing();
  }

  /// 接管完成后的 Image；已切换设备或源图变化时立即释放过期结果。
  void completeEditing(ui.Image source, ScreenshotEditResult result) {
    if (!ref.mounted || !state.isEditing || state.displayImage != source) {
      result.image.dispose();
      return;
    }
    final oldImage = _editedImage;
    _editedImage = result.image;
    state = state.copyWith(
      editedScreenshotBytes: result.bytes,
      editedImage: result.image,
      isEditing: false,
    );
    oldImage?.dispose();
  }

  /// 与截图替换、设备重置和 Provider 销毁共用，不能释放原始截图。
  void disposeEditedImage() {
    _editedImage?.dispose();
    _editedImage = null;
  }
}
