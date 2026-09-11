part of 'app_management_service.dart';

/// 每批最多 50 个应用；计数代表已处理，失败数量独立累计。
Stream<List<AdbPackage>> _enrichPackageIcons(
  AppManagementService service,
  String deviceId,
  List<AdbPackage> packages, {
  PackageRefreshCallback? onProgress,
  bool throwOnError = false,
  bool Function()? isActive,
}) async* {
  bool active() => isActive?.call() ?? true;
  final current = List<AdbPackage>.from(packages);
  var processed = 0;
  var failed = 0;
  try {
    if (!active() || current.isEmpty) return;
    await service._ensureIconHelperPushed(deviceId, throwOnError: throwOnError);
    if (!active()) return;
    final userId = await service._currentUserId(deviceId);
    const chunkSize = 50;
    for (var i = 0; i < current.length; i += chunkSize) {
      if (!active()) return;
      final end = (i + chunkSize).clamp(0, current.length);
      final remotePath = '${AppManagementService._remotePackageListPath}.$i';
      File? chunkFile;
      var updatedAny = false;
      try {
        chunkFile = await service._writePackageListFileForChunk(
          deviceId,
          current.sublist(i, end),
          i,
        );
        if (!active()) return;
        final push = await service._adb.run([
          '-s',
          deviceId,
          'push',
          chunkFile.path,
          remotePath,
        ], timeout: AppManagementService._fileTransferTimeout);
        if (!push.isSuccess) throw StateError(push.message);
        if (!active()) return;
        final result = await service._adb.shell(
          deviceId,
          'CLASSPATH=${AppManagementService._remoteDexPath} app_process /system/bin '
          'com.adbmanage.helper.PackageIconHelper $remotePath $userId',
          timeout: AppManagementService._metadataTimeout,
        );
        if (!result.isSuccess) throw StateError(result.message);
        if (!active()) return;
        final infos = service._parseIconHelperOutput(result.stdout);
        for (var j = i; j < end; j++) {
          if (!active()) return;
          final package = current[j];
          final info = infos[package.name];
          if (info == null) {
            failed++;
          } else {
            final localPath = await service._pullIconIfNeeded(deviceId, info);
            if (info.remotePath.isNotEmpty && localPath == null) failed++;
            current[j] = package.copyWith(
              label: info.label.isEmpty ? null : info.label,
              iconLocalPath: localPath,
              iconRemotePath: info.remotePath.isEmpty ? null : info.remotePath,
              signatureMd5: info.signatureMd5.isEmpty
                  ? null
                  : info.signatureMd5,
              firstInstallTime: info.firstInstallTime,
              lastUpdateTime: info.lastUpdateTime,
            );
            updatedAny = true;
          }
          processed++;
        }
      } catch (_) {
        // 单批失败继续后续批次，保留已更新信息并在最终结果中提示。
        failed += end - processed;
        processed = end;
      } finally {
        // 清理失败不能掩盖原始刷新结果；设备端清理沿用已有超时。
        try {
          if (chunkFile != null && await chunkFile.exists()) {
            await chunkFile.delete();
          }
        } catch (_) {}
        unawaited(
          service._adb
              .shell(deviceId, 'rm -f $remotePath')
              .then<void>((_) {}, onError: (Object _, StackTrace __) {}),
        );
      }
      if (!active()) return;
      onProgress?.call(
        PackageRefreshProgress(
          stage: PackageRefreshStage.enriching,
          processed: processed,
          total: current.length,
          failed: failed,
        ),
      );
      if (updatedAny) yield List<AdbPackage>.from(current);
    }
  } catch (_) {
    // 历史后台调用仍允许失败；手动任务必须接收到整体错误。
    if (throwOnError) rethrow;
  }
}
