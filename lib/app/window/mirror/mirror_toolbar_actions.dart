part of 'mirror_floating_toolbar.dart';

/// 截图和前台窗口弹窗复用原有业务流程，按钮与快捷键共用同一个入口。
extension _MirrorToolbarActions on _MirrorFloatingToolbarState {
  Future<void> _takeScreenshot(
    BuildContext context,
    String deviceId, {
    required bool saveToFile,
  }) async {
    try {
      final displayId = widget.controller.isAppMirror
          ? ref
                .read(embeddedScrcpyServiceProvider)
                .getVirtualDisplayId(deviceId)
          : null;
      if (widget.controller.isAppMirror && displayId == null) {
        throw StateError('应用副屏尚未准备完成，无法截图');
      }
      final bytes = widget.controller.isIos
          ? await ref
                .read(iosCommandServiceProvider)
                .captureScreenshot(deviceId)
          : (widget.controller.isHarmony
                ? await ref.read(hdcServiceProvider).captureScreenshot(deviceId)
                : (displayId == null
                      ? await ref
                            .read(adbServiceProvider)
                            .captureScreenshot(deviceId)
                      : await ref
                            .read(adbServiceProvider)
                            .captureDisplayScreenshot(deviceId, displayId)));

      final hostPlatform = ref.read(hostPlatformServiceProvider);

      // 复制到剪切板
      final copied = await hostPlatform.copyImageToClipboard(bytes);

      if (saveToFile) {
        final settings = ref.read(appSettingsProvider);
        final savePath = hostPlatform.generateScreenshotPath(
          settings.screenshotSavePath,
          deviceId,
        );
        final file = File(savePath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);

        if (context.mounted) {
          AppToast.show(
            context,
            '${context.l10n.t('saveSuccess')}: $savePath${copied ? " (已复制到剪贴板)" : ""}',
          );
        }
      } else {
        if (context.mounted) {
          if (copied) {
            AppToast.show(context, context.l10n.t('copySuccess'));
          } else {
            AppToast.show(
              context,
              context.l10n.locale.languageCode == 'zh'
                  ? '复制至剪贴板失败'
                  : 'Failed to copy to clipboard',
              isError: true,
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, '${context.l10n.t('error')}: $e', isError: true);
      }
    }
  }

  Future<void> _showForegroundWindow(
    BuildContext context,
    DeviceActionService actions,
  ) async {
    if (!widget.controller.isHarmony) {
      // Android 设备同步刷新标题栏的前台应用 icon。
      widget.controller.identifyForegroundApp();
    }

    final res = widget.controller.isHarmony
        ? await ref.read(hdcServiceProvider).currentFocus(widget.deviceId)
        : await actions.currentFocus(widget.deviceId);
    final harmonyWindow = widget.controller.isHarmony
        ? HarmonyForegroundWindow.parse(res.stdout)
        : null;
    if (context.mounted) {
      showDialog<void>(
        context: context,
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final cardColor = isDark
              ? const Color(0xff1e1e1e)
              : const Color(0xffffffff);
          return AlertDialog(
            backgroundColor: cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            title: Row(
              children: [
                Icon(
                  CupertinoIcons.scope,
                  color: Theme.of(context).appColors.toolbarForeground,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.t('currentFocusWindow'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: SelectableText(
              harmonyWindow == null
                  ? res.message
                  : formatMirrorHarmonyFocus(
                      context,
                      harmonyWindow,
                      fallback: res.isSuccess
                          ? context.l10n.t('foregroundUnavailable')
                          : res.message,
                    ),
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  context.l10n.t('ok'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          );
        },
      );
    }
  }
}
