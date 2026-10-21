import 'package:flutter/material.dart';

import '../../../core/harmony/harmony_foreground_window.dart';
import '../../l10n/app_localizations.dart';

/// 将前台窗口信息转换为投屏弹框的本地化摘要。
String formatMirrorHarmonyFocus(
  BuildContext context,
  HarmonyForegroundWindow window, {
  required String fallback,
}) {
  if (window.isEmpty) return fallback;
  final missing = context.l10n.t('foregroundUnknown');
  final page = window.pageName ?? window.abilityName?.split('.').last;
  return [
    '${context.l10n.t('foregroundPage')}: ${page ?? missing}',
    '${context.l10n.t('foregroundAppId')}: ${window.bundleName ?? missing}',
    '${context.l10n.t('foregroundAbility')}: ${window.abilityName ?? missing}',
    '${context.l10n.t('foregroundWindow')}: ${window.windowName ?? missing}',
  ].join('\n');
}
