import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../core/ios/ios_control_provider.dart';

/// 控制页与投屏窗口共用的启停入口。udid 决定主引擎中的唯一 WDA 会话。
class IosControlBar extends ConsumerWidget {
  const IosControlBar({super.key, required this.udid});
  final String udid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(iosControlProvider(udid));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () => ref
                  .read(iosControlProvider(udid).notifier)
                  .perform(state.ready || state.busy ? 'stop' : 'start'),
              icon: state.busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(state.ready ? Icons.mouse : Icons.touch_app_outlined),
              label: Text(
                context.l10n.t(
                  state.busy
                      ? 'iosCancelControl'
                      : state.ready
                      ? 'iosStopControl'
                      : 'iosStartControl',
                ),
              ),
            ),
            Text(
              context.l10n.t(state.ready ? 'iosControlReady' : 'iosControlOff'),
            ),
          ],
        ),
        if (state.error != null)
          Text(
            iosControlErrorText(context, state.error!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

/// 底层使用稳定错误 key，已知前置条件翻译为可执行提示，其余保留诊断细节。
String iosControlErrorText(BuildContext context, String error) {
  for (final key in [
    'iosWdaRunnerMissing',
    'iosWdaProxyMissing',
    'iosWdaUnavailable',
    'iosControlBusy',
    'iosUsbTextureFailed',
    'iosUsbDeviceAmbiguous',
    'iosUsbDeviceMissing',
    'iosUsbPermissionDenied',
    'iosUsbFirstFrameTimeout',
    'iosUsbCaptureStopped',
    'iosUsbMacOnly',
    'iosUsbStarting',
    'iosControlClosed',
  ]) {
    if (error.contains(key)) return context.l10n.t(key);
  }
  return error;
}
