import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../multi_window_compat.dart';

/// 打开或置前唯一的独立控制台；由调用方决定是否收起底部面板。
Future<bool> openConsoleWindow(BuildContext context) async {
  final title = context.l10n.t('console');
  final failure = context.l10n.t('consoleWindowFailed');
  try {
    await createAdbManageWindow(
      arguments: const {'type': 'console'},
      frame: const Offset(150, 150) & const Size(950, 550),
      title: title,
    );
    return true;
  } catch (error) {
    debugPrint('Failed to open console window: $error');
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure)));
    }
    return false;
  }
}
