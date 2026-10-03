import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_log_recorder.dart';
import 'log_service.dart';

/// 在每个 Flutter Engine 启动时安装异常及 debugPrint 捕获，保留原有错误输出。
void installAppLogCapture() {
  final recorder = AppLogRecorder.instance;
  final originalPrint = debugPrint;
  var reporting = false;
  debugPrint = (message, {wrapWidth}) {
    if (!reporting && message != null) {
      recorder.record(
        message,
        tag: 'runtime',
        level: AppLogRecorder.runtimeLevel(message),
      );
    }
    originalPrint(message, wrapWidth: wrapWidth);
  };
  final originalFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    recorder.record(
      '${details.exceptionAsString()}\n${details.stack ?? ''}',
      tag: 'flutter',
      level: 'E',
    );
    reporting = true;
    try {
      originalFlutterError?.call(details);
    } finally {
      reporting = false;
    }
  };
  final originalPlatformError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    recorder.record('$error\n$stack', tag: 'platform', level: 'E');
    return originalPlatformError?.call(error, stack) ?? false;
  };
}

/// 子窗口根节点预热日志订阅；[child] 为原窗口应用，不引入额外 UI。
class AppLogScope extends ConsumerWidget {
  const AppLogScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(logHistoryProvider.notifier);
    return child;
  }
}
