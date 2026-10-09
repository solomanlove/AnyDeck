import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../core/adb/adb_result.dart';
import '../../core/providers/app_providers.dart';
import '../widgets/dashboard_snack.dart';

/// 控制面板和手机设置弹窗共用的跳转反馈，不向用户透出原始命令输出。
Future<void> runDeeplinkAction(
  BuildContext context,
  WidgetRef ref,
  Future<AdbResult> future,
) async {
  var succeeded = false;
  try {
    final result = await future;
    if (!context.mounted) return;
    if (result.isDeviceDisconnected) {
      await ref
          .read(deviceRegistryProvider.notifier)
          .syncAfterAdbResult(result);
    }
    // 某些 am start 失败仍返回 0；仅匹配错误行，避免误判 Intent URI。
    final hasLaunchError = RegExp(
      r'^\s*(?:Error:|Error type \d+|Exception occurred while executing|java\.lang\.\w*Exception:|SecurityException:)',
      multiLine: true,
      caseSensitive: false,
    ).hasMatch('${result.stdout}\n${result.stderr}');
    succeeded = result.isSuccess && !hasLaunchError;
  } catch (_) {
    // 超时或进程异常与命令失败使用同一友好提示。
  }
  if (!context.mounted) return;
  DashboardSnack.show(
    context,
    context.l10n.t(succeeded ? 'deeplinkSuccess' : 'deeplinkFailed'),
    isError: !succeeded,
  );
}
