import '../adb/adb_result.dart';
import '../adb/adb_service.dart';

// 只匹配 Window 记录中用户标识后的组件，跳过 null 和系统窗口标题。
final _focusComponent = RegExp(
  r'^[ \t]*mCurrentFocus=Window\{\S+[ \t]+u\d+[ \t]+'
  r'(\w+(?:\.\w+)*)/(\.?[\p{L}\p{M}\p{N}_$]+(?:\.[\p{L}\p{M}\p{N}_$]+)*)(?=[ \t}])',
  multiLine: true,
  unicode: true,
);

/// 查询 Android 焦点窗口，多屏结果按设备返回顺序去重，每行一个完整组件名。
Future<AdbResult> readAndroidForegroundWindow(
  AdbService adb,
  String deviceId,
) async {
  final result = await adb.shell(
    deviceId,
    'dumpsys window | grep mCurrentFocus',
  );
  if (!result.isSuccess) return result;

  final components = <String>{};
  for (final match in _focusComponent.allMatches(result.stdout)) {
    final package = match[1]!;
    final activity = match[2]!;
    final className = activity.startsWith('.') ? '$package$activity' : activity;
    components.add('$package/$className');
  }
  return AdbResult(
    exitCode: result.exitCode,
    stdout: components.join('\n'),
    stderr: result.stderr,
  );
}
