part of '../harmony_control_tab.dart';

/// 鸿蒙控制页的系统快捷操作，复用已存在的 HDC、截图和录屏服务。
extension _HarmonyControlQuickActions on _HarmonyControlTabState {
  List<Widget> _buildSystemQuickActions(BuildContext context) {
    final isRecording = ref.watch(
      screenRecordProvider(widget.device.id).select((state) => state.isRecording),
    );
    final isStopping = ref.watch(
      screenRecordProvider(widget.device.id).select((state) => state.isStopping),
    );
    return [
      OutlinedButton.icon(
        icon: const Icon(CupertinoIcons.settings, size: 16),
        label: Text(context.l10n.t('deviceSettings')),
        onPressed: () => _executeHdcAction(
          context.l10n.t('deviceSettings'),
          (hdc) => hdc.openSettings(widget.device.id, HarmonySettingsPage.main),
        ),
      ),
      OutlinedButton.icon(
        icon: const Icon(CupertinoIcons.bell, size: 16),
        label: Text(context.l10n.t('notificationBar')),
        onPressed: () => _executeHdcAction(
          context.l10n.t('notificationBar'),
          (hdc) => hdc.openSystemPanel(widget.device.id, quickSettings: false),
        ),
      ),
      OutlinedButton.icon(
        icon: const Icon(CupertinoIcons.slider_horizontal_3, size: 16),
        label: Text(context.l10n.t('expandSettings')),
        onPressed: () => _executeHdcAction(
          context.l10n.t('expandSettings'),
          (hdc) => hdc.openSystemPanel(widget.device.id, quickSettings: true),
        ),
      ),
      OutlinedButton.icon(
        icon: const Icon(CupertinoIcons.camera, size: 16),
        label: Text(context.l10n.t('screenshot')),
        onPressed: _captureScreenshot,
      ),
      OutlinedButton.icon(
        icon: Icon(
          isRecording ? CupertinoIcons.stop_circle : CupertinoIcons.recordingtape,
          size: 16,
        ),
        label: Text(context.l10n.t(isRecording ? 'stopRecord' : 'screenRecord')),
        onPressed: isStopping
            ? null
            : () => toggleMirrorScreenRecording(context, ref, widget.device.id),
      ),
    ];
  }

  /// 复用截图页的本地保存与剪贴板流程。
  Future<void> _captureScreenshot() async {
    try {
      final bytes = await ref.read(hdcServiceProvider).captureScreenshot(widget.device.id);
      if (!mounted) return;
      await ScreenshotExportHelper.saveScreenshot(
        context,
        deviceId: widget.device.id,
        rawBytes: bytes,
        settings: ref.read(appSettingsProvider),
        hostPlatform: ref.read(hostPlatformServiceProvider),
      );
    } catch (error) {
      if (mounted) {
        DashboardSnack.show(context, '${context.l10n.t('error')}: $error', isError: true);
      }
    }
  }
}
