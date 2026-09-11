import 'dart:io';
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
        backgroundColor: const Color(0xff09c47c),
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
          backgroundColor: success ? const Color(0xff09c47c) : Colors.red,
          behavior: SnackBarBehavior.floating,
          width: 300,
        ),
      );
    }
  }

  /// 保存截图（若在分析模式下且具备 XML，则同时导出 PNG 与 XML 配对文件）
  static Future<void> saveScreenshotOrExport(
    BuildContext context, {
    required String deviceId,
    required Uint8List? rawBytes,
    required bool isLayoutAnalysis,
    required String? xmlContent,
    required AppSettings settings,
    required HostPlatformService hostPlatform,
  }) async {
    if (rawBytes == null) return;

    if (isLayoutAnalysis && xmlContent != null) {
      try {
        final location = await getSaveLocation(
          acceptedTypeGroups: [
            const XTypeGroup(label: 'PNG Image', extensions: ['png']),
          ],
          suggestedName:
              'layout_${deviceId}_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        if (location == null) return;

        final basePath = location.path;
        final pngFile = File(basePath);
        await pngFile.writeAsBytes(rawBytes);

        final xmlPath =
            '${basePath.replaceAll(RegExp(r'\.png$', caseSensitive: false), '')}.xml';
        final xmlFile = File(xmlPath);
        await xmlFile.writeAsString(xmlContent);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已成功保存截图与 XML 至: $basePath'),
              backgroundColor: const Color(0xff09c47c),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('保存失败: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } else {
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
                '${context.l10n.t('saveSuccess')}: $savePath${copied ? " (已复制到剪贴板)" : ""}',
              ),
              backgroundColor: const Color(0xff09c47c),
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
  }
}
