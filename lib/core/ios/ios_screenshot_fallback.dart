import 'dart:io';

import 'package:flutter/services.dart';

import 'ios_screenshot_capture.dart';

/// macOS USB 截图回退：打包提取 helper，复用命令执行器的超时和进程回收。
Future<Uint8List> captureIosScreenshotFallback(
  String udid, {
  required String iosExecutable,
  required IosScreenshotCommand runPython,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'anydeck_screenshotr_',
  );
  try {
    for (final name in ['ios_icon_helper.py', 'ios_screenshot_helper.py']) {
      final data = await rootBundle.load('assets/ios/$name');
      await File('${directory.path}/$name').writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    }
    final file = File('${directory.path}/screenshot.png');
    final result = await runPython([
      '${directory.path}/ios_screenshot_helper.py',
      '--udid=$udid',
      '--ios-path=$iosExecutable',
      '--output=${file.path}',
    ], timeout: const Duration(seconds: 20));
    if (!result.isSuccess) throw Exception(result.message);
    if (!await file.exists() || await file.length() == 0) {
      throw StateError('screenshotr returned no image');
    }
    return await file.readAsBytes();
  } finally {
    await directory.delete(recursive: true);
  }
}
