import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../core/providers/app_providers.dart';
import '../controller/screenshot_controller.dart';

/// 长按自动刷新截图触发的配置弹窗。
/// 支持配置是否开启自动保存、保存目录选择及刷新时间间隔。
class ScreenshotAutoSaveDialog extends ConsumerStatefulWidget {
  const ScreenshotAutoSaveDialog({
    super.key,
    required this.deviceId,
  });

  final String deviceId;

  /// 便捷展示配置对话框
  static Future<void> show({
    required BuildContext context,
    required String deviceId,
  }) {
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) => ScreenshotAutoSaveDialog(deviceId: deviceId),
    );
  }

  @override
  ConsumerState<ScreenshotAutoSaveDialog> createState() =>
      _ScreenshotAutoSaveDialogState();
}

class _ScreenshotAutoSaveDialogState
    extends ConsumerState<ScreenshotAutoSaveDialog> {
  late bool _autoSave;
  late String _savePath;
  late int _intervalSeconds;

  @override
  void initState() {
    super.initState();
    final state =
        ref.read(screenshotLayoutControllerProvider(widget.deviceId));
    final settings = ref.read(appSettingsProvider);
    final hostPlatform = ref.read(hostPlatformServiceProvider);

    _autoSave = state.isAutoSave || !state.isAutoRefresh;
    if (state.autoSavePath.isNotEmpty) {
      _savePath = state.autoSavePath;
    } else if (settings.screenshotSavePath.isNotEmpty) {
      _savePath = settings.screenshotSavePath;
    } else {
      _savePath = hostPlatform.getSaveDirectory('');
    }
    _intervalSeconds = state.autoRefreshInterval > 0
        ? state.autoRefreshInterval
        : 3;
  }

  Future<void> _chooseDirectory() async {
    final selected = await getDirectoryPath(
      initialDirectory: _savePath.isNotEmpty && Directory(_savePath).existsSync()
          ? _savePath
          : null,
    );
    if (selected != null && mounted) {
      setState(() {
        _savePath = selected;
      });
    }
  }

  void _openDirectory() {
    if (_savePath.isNotEmpty) {
      ref.read(hostPlatformServiceProvider).openDirectory(_savePath);
    }
  }

  void _submit() {
    final controller = ref.read(
      screenshotLayoutControllerProvider(widget.deviceId).notifier,
    );
    controller.updateAutoRefreshConfig(
      autoSave: _autoSave,
      savePath: _savePath,
      intervalSeconds: _intervalSeconds,
      startImmediately: true,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final cardColor = isDark
        ? const Color(0xff1e1e1e)
        : const Color(0xffffffff);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.08);

    const availableIntervals = [1, 2, 3, 5, 10];

    return AlertDialog(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              CupertinoIcons.clock_fill,
              color: primaryColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            context.l10n.t('autoSaveScreenshotSettings'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 自动保存开关
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.t('enableAutoSaveScreenshot'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            context.l10n.t('autoSaveHint'),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoSwitch(
                      value: _autoSave,
                      activeTrackColor: primaryColor,
                      onChanged: (val) {
                        setState(() {
                          _autoSave = val;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 2. 保存目录选择
              Text(
                context.l10n.t('autoSaveDirLabel'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.folder,
                      size: 18,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _savePath.isEmpty
                            ? context.l10n.t('notSetDefaultPath')
                            : _savePath,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[200] : Colors.grey[850],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_savePath.isNotEmpty) ...[
                      IconButton(
                        tooltip: context.l10n.t('openFolder'),
                        icon: const Icon(CupertinoIcons.folder_open, size: 18),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        onPressed: _openDirectory,
                      ),
                      const SizedBox(width: 4),
                    ],
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: _chooseDirectory,
                      child: Text(
                        context.l10n.t('chooseFolder'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 3. 刷新间隔
              Text(
                context.l10n.t('autoSaveInterval'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: availableIntervals.map((sec) {
                  final isSelected = _intervalSeconds == sec;
                  return ChoiceChip(
                    label: Text('${sec}s'),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _intervalSeconds = sec;
                        });
                      }
                    },
                    selectedColor: primaryColor.withValues(alpha: 0.18),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected
                          ? primaryColor
                          : (isDark ? Colors.grey[300] : Colors.grey[800]),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected ? primaryColor : borderColor,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.t('cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: _submit,
          child: Text(context.l10n.t('saveAndApply')),
        ),
      ],
    );
  }
}
