import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../apps/widgets/camera_preview_view.dart';

/// 控制 Tab 的摄像头预览弹窗。
///
/// 仅包装 [CameraPreviewView]：打开弹窗不自动启动摄像头，用户点击开始才采集；
/// 关闭弹窗即移除 [CameraPreviewView]，自动释放其 autoDispose Provider 会话。
class CameraPreviewDialog extends StatelessWidget {
  const CameraPreviewDialog({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.t('cameraTitle')),
      content: SizedBox(
        width: 820,
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: CameraPreviewView(deviceId: deviceId),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.t('close')),
        ),
      ],
    );
  }
}