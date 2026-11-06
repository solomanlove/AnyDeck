import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/process/host_platform_service.dart';
import 'screenshot_export_helper.dart';

/// 自动保存的 IO 接口；允许用慢磁盘桩验证采集与落盘的背压。
typedef ScreenshotAutoSaveWriter =
    Future<String?> Function({
      required String deviceId,
      required Uint8List? rawBytes,
      required String targetPath,
      required HostPlatformService hostPlatform,
    });

final screenshotAutoSaveWriterProvider = Provider<ScreenshotAutoSaveWriter>(
  (ref) => ScreenshotExportHelper.autoSaveScreenshot,
);
