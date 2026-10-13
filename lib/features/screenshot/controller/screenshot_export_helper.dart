import 'dart:io';
import 'package:any_deck/app/theme/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/settings/app_settings.dart';
import '../../../core/layout_inspector/layout_node.dart';
import '../../../core/process/host_platform_service.dart';

/// 截图与布局导出辅助工具类。
class ScreenshotExportHelper {
  const ScreenshotExportHelper._();

  /// 复制当前选中节点（或根节点）的 XML 到系统剪贴板
  static void copySelectedXml(
    BuildContext context, {
    required LayoutNode? selectedNode,
    required LayoutNode? rootNode,
  }) {
    final node = selectedNode ?? rootNode;
    if (node == null) return;
    Clipboard.setData(ClipboardData(text: node.toXmlString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.t('copySuccess')),
        duration: const Duration(seconds: 1),
        backgroundColor: AppPalette.primary,
        behavior: SnackBarBehavior.floating,
        width: 300,
      ),
    );
  }

  /// 复制当前截图二进制数据到系统剪贴板
  static Future<void> copyScreenshotImage(
    BuildContext context, {
    required Uint8List? bytes,
    required HostPlatformService hostPlatform,
  }) async {
    if (bytes == null) return;
    final success = await hostPlatform.copyImageToClipboard(bytes);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? context.l10n.t('copySuccess') : '复制到剪贴板失败'),
          backgroundColor: success ? AppPalette.primary : Colors.red,
          behavior: SnackBarBehavior.floating,
          width: 300,
        ),
      );
    }
  }

  /// 保存当前截图，并沿用截图工作台的剪贴板同步行为。
  static Future<void> saveScreenshot(
    BuildContext context, {
    required String deviceId,
    required Uint8List? rawBytes,
    required AppSettings settings,
    required HostPlatformService hostPlatform,
  }) async {
    if (rawBytes == null) return;

    try {
      final savePath = hostPlatform.generateScreenshotPath(
        settings.screenshotSavePath,
        deviceId,
      );
      final file = File(savePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(rawBytes);

      final copied = await hostPlatform.copyImageToClipboard(rawBytes);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.l10n.t('saveSuccess')}: $savePath${copied ? " (${context.l10n.t('copySuccess')})" : ""}',
            ),
            backgroundColor: AppPalette.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
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

  /// 将当前完整布局 XML 导出为独立文件。
  static Future<void> exportXml(
    BuildContext context, {
    required String deviceId,
    required String? xmlContent,
  }) async {
    if (xmlContent == null || xmlContent.isEmpty) return;
    try {
      final location = await getSaveLocation(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'XML', extensions: ['xml']),
        ],
        suggestedName:
            'layout_${deviceId}_${DateTime.now().millisecondsSinceEpoch}.xml',
      );
      if (location == null) return;
      await File(location.path).writeAsString(xmlContent);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n
                  .t('xmlExportSuccess')
                  .replaceAll('{path}', location.path),
            ),
            backgroundColor: AppPalette.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
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

  /// 自动刷新模式下静默保存截图到指定目录（不干扰系统剪贴板）
  static Future<String?> autoSaveScreenshot({
    required String deviceId,
    required Uint8List? rawBytes,
    required String targetPath,
    required HostPlatformService hostPlatform,
  }) async {
    if (rawBytes == null) return null;
    try {
      final savePath = hostPlatform.generateScreenshotPath(
        targetPath,
        deviceId,
      );
      final file = File(savePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(rawBytes);
      return savePath;
    } catch (_) {
      return null;
    }
  }
}

