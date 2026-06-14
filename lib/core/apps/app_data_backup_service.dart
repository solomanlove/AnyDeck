import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../adb/adb_result.dart';
import '../adb/adb_service.dart';

/// 应用数据备份门面，按 Android 版本和权限能力选择可行的数据导出/恢复路径。
class AppDataBackupService {
  AppDataBackupService(this._adb);

  final AdbService _adb;

  static const _operationTimeout = Duration(minutes: 10);
  static final _packageNamePattern = RegExp(r'^[A-Za-z0-9_.]+$');

  Future<AdbResult> backupData(
    String deviceId,
    String packageName,
    String directory, {
    String? displayName,
    String? versionName,
  }) async {
    if (!_isSafePackageName(packageName)) {
      return const AdbResult(exitCode: 2, stdout: '', stderr: '包名不合法，已取消备份');
    }

    final sdk = await _readSdkVersion(deviceId);
    final useLegacyBackup = sdk != null && sdk <= 30;
    final extension = useLegacyBackup ? 'ab' : 'tar';
    final localPath = _buildLocalBackupPath(
      directory,
      packageName,
      displayName: displayName,
      versionName: versionName,
      extension: extension,
    );

    if (useLegacyBackup) {
      final legacyResult = await _legacyBackup(
        deviceId,
        packageName,
        localPath,
      );
      if (_isUsableLocalFile(localPath)) {
        return AdbResult(
          exitCode: 0,
          stdout: localPath,
          stderr: legacyResult.stderr,
        );
      }
      final fallbackPath = _buildLocalBackupPath(
        directory,
        packageName,
        displayName: displayName,
        versionName: versionName,
        extension: 'tar',
      );
      final fallbackResult = await _backupDataAsTar(
        deviceId,
        packageName,
        fallbackPath,
        sdk,
      );
      return fallbackResult.isSuccess
          ? fallbackResult
          : _appendSystemHint(legacyResult, sdk);
    }

    return _backupDataAsTar(deviceId, packageName, localPath, sdk);
  }

  Future<AdbResult> _backupDataAsTar(
    String deviceId,
    String packageName,
    String localPath,
    int? sdk,
  ) async {
    final runAsResult = await _backupWithRunAs(
      deviceId,
      packageName,
      localPath,
    );
    if (runAsResult.isSuccess && _isUsableLocalFile(localPath)) {
      return AdbResult(
        exitCode: 0,
        stdout: localPath,
        stderr: runAsResult.stderr,
      );
    }

    final rootResult = await _backupWithRoot(deviceId, packageName, localPath);
    if (rootResult.isSuccess && _isUsableLocalFile(localPath)) {
      return AdbResult(
        exitCode: 0,
        stdout: localPath,
        stderr: rootResult.stderr,
      );
    }

    return _mergeFailure(
      primary: runAsResult,
      fallback: rootResult,
      sdk: sdk,
      action: '备份',
    );
  }

  Future<AdbResult> restoreData(
    String deviceId,
    String packageName,
    String localPath,
  ) async {
    if (!_isSafePackageName(packageName)) {
      return const AdbResult(exitCode: 2, stdout: '', stderr: '包名不合法，已取消恢复');
    }
    if (!File(localPath).existsSync()) {
      return AdbResult(exitCode: 2, stdout: '', stderr: '备份文件不存在: $localPath');
    }

    final sdk = await _readSdkVersion(deviceId);
    if (localPath.toLowerCase().endsWith('.ab')) {
      final result = await _legacyRestore(deviceId, localPath);
      return result.isSuccess ? result : _appendSystemHint(result, sdk);
    }

    final runAsResult = await _restoreWithRunAs(
      deviceId,
      packageName,
      localPath,
    );
    if (runAsResult.isSuccess) {
      return runAsResult;
    }

    final rootResult = await _restoreWithRoot(deviceId, packageName, localPath);
    if (rootResult.isSuccess) {
      return rootResult;
    }

    return _mergeFailure(
      primary: runAsResult,
      fallback: rootResult,
      sdk: sdk,
      action: '恢复',
    );
  }

  Future<int?> _readSdkVersion(String deviceId) async {
    final result = await _adb.shellArgs(deviceId, [
      'getprop',
      'ro.build.version.sdk',
    ]);
    if (!result.isSuccess) {
      return null;
    }
    return int.tryParse(result.stdout.trim());
  }

  Future<AdbResult> _legacyBackup(
    String deviceId,
    String packageName,
    String localPath,
  ) {
    return _adb.run([
      '-s',
      deviceId,
      'backup',
      '-f',
      localPath,
      '-noapk',
      packageName,
    ], timeout: _operationTimeout);
  }

  Future<AdbResult> _legacyRestore(String deviceId, String localPath) {
    return _adb.run([
      '-s',
      deviceId,
      'restore',
      localPath,
    ], timeout: _operationTimeout);
  }

  Future<AdbResult> _backupWithRunAs(
    String deviceId,
    String packageName,
    String localPath,
  ) {
    return _runStdoutToFile([
      '-s',
      deviceId,
      'exec-out',
      'run-as',
      packageName,
      'tar',
      '-C',
      '/data/data/$packageName',
      '-cf',
      '-',
      '.',
    ], localPath);
  }

  Future<AdbResult> _restoreWithRunAs(
    String deviceId,
    String packageName,
    String localPath,
  ) {
    return _runFileToStdin([
      '-s',
      deviceId,
      'exec-in',
      'run-as',
      packageName,
      'tar',
      '-C',
      '/data/data/$packageName',
      '-xf',
      '-',
    ], localPath);
  }

  Future<AdbResult> _backupWithRoot(
    String deviceId,
    String packageName,
    String localPath,
  ) async {
    final remotePath = _remoteTarPath(packageName);
    final tarResult = await _adb.shellArgs(deviceId, [
      'su',
      '-c',
      'tar -C /data/data/$packageName -cf $remotePath . && chmod 0644 $remotePath',
    ], timeout: _operationTimeout);
    if (!tarResult.isSuccess) {
      return tarResult;
    }

    final pullResult = await _adb.run([
      '-s',
      deviceId,
      'pull',
      remotePath,
      localPath,
    ], timeout: _operationTimeout);
    await _adb.shellArgs(deviceId, ['rm', '-f', remotePath]);
    return pullResult;
  }

  Future<AdbResult> _restoreWithRoot(
    String deviceId,
    String packageName,
    String localPath,
  ) async {
    final remotePath = _remoteTarPath(packageName);
    final pushResult = await _adb.run([
      '-s',
      deviceId,
      'push',
      localPath,
      remotePath,
    ], timeout: _operationTimeout);
    if (!pushResult.isSuccess) {
      return pushResult;
    }

    final ownerResult = await _adb.shellArgs(deviceId, [
      'su',
      '-c',
      'stat -c %u:%g /data/data/$packageName',
    ]);
    final owner = ownerResult.stdout.trim();
    final chownCommand = ownerResult.isSuccess && owner.isNotEmpty
        ? ' && chown -R $owner /data/data/$packageName'
        : '';
    final restoreResult = await _adb.shellArgs(deviceId, [
      'su',
      '-c',
      'tar -C /data/data/$packageName -xf $remotePath$chownCommand && restorecon -R /data/data/$packageName',
    ], timeout: _operationTimeout);
    await _adb.shellArgs(deviceId, ['rm', '-f', remotePath]);
    return restoreResult;
  }

  Future<AdbResult> _runStdoutToFile(
    List<String> args,
    String localPath,
  ) async {
    Process? process;
    IOSink? sink;
    try {
      process = await Process.start(_adb.executable, args);
      sink = File(localPath).openWrite();
      final stdoutFuture = process.stdout.pipe(sink);
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(_operationTimeout);
      await stdoutFuture;
      final stderr = await stderrFuture;
      return AdbResult(exitCode: exitCode, stdout: localPath, stderr: stderr);
    } on TimeoutException {
      process?.kill();
      await process?.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process?.kill(ProcessSignal.sigkill);
          return 124;
        },
      );
      await sink?.close();
      return const AdbResult(exitCode: 124, stdout: '', stderr: '应用数据备份超时');
    } on ProcessException catch (error) {
      await sink?.close();
      return AdbResult(exitCode: 127, stdout: '', stderr: error.message);
    } catch (error) {
      await sink?.close();
      return AdbResult(exitCode: 1, stdout: '', stderr: error.toString());
    }
  }

  Future<AdbResult> _runFileToStdin(List<String> args, String localPath) async {
    Process? process;
    try {
      process = await Process.start(_adb.executable, args);
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      
      // 异步进行管道写入，防止阻塞整体超时流程
      final pipeFuture = File(localPath).openRead().pipe(process.stdin);
      
      // 等待写入和进程退出，应用整体超时保护
      await Future.wait([
        pipeFuture.catchError((_) => null), // 忽略管道写入异常（如进程中途退出）
        process.exitCode,
      ]).timeout(_operationTimeout);

      final exitCode = await process.exitCode;
      final stderr = await stderrFuture;
      return AdbResult(exitCode: exitCode, stdout: '命令执行完成', stderr: stderr);
    } on TimeoutException {
      process?.kill();
      await process?.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process?.kill(ProcessSignal.sigkill);
          return 124;
        },
      );
      return const AdbResult(exitCode: 124, stdout: '', stderr: '应用数据恢复超时');
    } on ProcessException catch (error) {
      return AdbResult(exitCode: 127, stdout: '', stderr: error.message);
    } catch (error) {
      return AdbResult(exitCode: 1, stdout: '', stderr: error.toString());
    }
  }

  AdbResult _appendSystemHint(AdbResult result, int? sdk) {
    final hint = _systemVersionHint(sdk);
    return AdbResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: '${result.message}\n$hint',
    );
  }

  AdbResult _mergeFailure({
    required AdbResult primary,
    required AdbResult fallback,
    required int? sdk,
    required String action,
  }) {
    final hint = _systemVersionHint(sdk);
    return AdbResult(
      exitCode: fallback.exitCode == 0 ? primary.exitCode : fallback.exitCode,
      stdout: '',
      stderr:
          '$action应用数据失败。\nrun-as: ${primary.message}\nroot: ${fallback.message}\n$hint',
    );
  }

  String _systemVersionHint(int? sdk) {
    if (sdk == null) {
      return '未能识别 Android API 级别；请确认设备在线，并检查应用是否 debuggable、设备是否 Root。';
    }
    if (sdk <= 30) {
      return 'Android API $sdk 优先使用 adb backup/restore，设备端需要手动确认，且应用 allowBackup=false 时会得到空备份。';
    }
    return 'Android API $sdk 已弱化/移除 legacy adb backup；非 debuggable 应用通常需要 Root 才能备份或恢复 /data/data。';
  }

  String _buildLocalBackupPath(
    String directory,
    String packageName, {
    String? displayName,
    String? versionName,
    required String extension,
  }) {
    final label = (displayName == null || displayName.isEmpty)
        ? packageName
        : displayName;
    final safeLabel = label.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final safeVersion = versionName == null || versionName.isEmpty
        ? ''
        : '_v${versionName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}';
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '');
    return '$directory/${safeLabel}_data$safeVersion.$timestamp.$extension';
  }

  String _remoteTarPath(String packageName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '/data/local/tmp/adbmanage_${packageName}_$timestamp.tar';
  }

  bool _isUsableLocalFile(String path) {
    final file = File(path);
    return file.existsSync() && file.lengthSync() > 0;
  }

  bool _isSafePackageName(String packageName) {
    return _packageNamePattern.hasMatch(packageName);
  }
}
