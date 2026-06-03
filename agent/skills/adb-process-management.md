# Skill: adb-process-management (CLI 进程安全设计)

## 概述
本技能负责管理后台外部进程（如 ADB shell、交互式 terminal、scrcpy 投屏流）的生命周期。确保命令行在后台运行时，资源开销可控、命令参数安全，并且能在连接中断或 UI 退出时被 100% 回收。

## 典型操作模式

### 1. 单次阻塞命令（带超时拦截）
使用 `Process.start` 启动命令，并附加 `TimeoutException` 处理逻辑：
```dart
Future<AdbResult> runCommand(List<String> args, {Duration timeout = const Duration(seconds: 15)}) async {
  Process? process;
  try {
    process = await Process.start('adb', args);
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode.timeout(timeout);
    return AdbResult(exitCode: exitCode, stdout: await stdoutFuture, stderr: await stderrFuture);
  } on TimeoutException {
    process?.kill(); // 尝试正常结束
    await process?.exitCode.timeout(const Duration(seconds: 2), onTimeout: () {
      process?.kill(ProcessSignal.sigkill); // 强制终止
      return -1;
    });
    return AdbResult(exitCode: 124, stdout: '', stderr: 'Timeout');
  } catch (e) {
    return AdbResult(exitCode: -1, stdout: '', stderr: e.toString());
  }
}
```

### 2. 长生存期持续流（如实时 Logcat/终端）
- 必须利用 Riverpod 的 `ref.onDispose` 挂载回收勾子。
- 确保在 UI Tab 销毁或切换设备时，主动终止前一个子进程：
```dart
final logcatStreamProvider = StreamProvider.autoDispose((ref) async* {
  final deviceId = ref.watch(selectedDeviceProvider);
  final process = await Process.start('adb', ['-s', deviceId, 'logcat']);
  
  ref.onDispose(() {
    process.kill(ProcessSignal.sigkill); // 释放后台 logcat 监听
  });
  
  yield* process.stdout.transform(utf8.decoder).transform(const LineSplitter());
});
```

### 3. 安全防护规约
- 绝不允许将命令行拼接为原始长字符串通过 `sh -c` 执行。
- 限制并发 ADB 命令数量：批量命令（如批量安装 APK）应采用队列方式（异步串行），避免瞬时并发过多 `Process.start` 导致 CPU 占用率飙升或 adb server 崩溃。
- 检测并抛出显式异常，禁止在底层捕获异常后吞掉错误。
