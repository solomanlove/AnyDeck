part of 'share_transfer_history.dart';

/// 接收中的子文件快照与摘要共用原有容量预留、检查点和失败事务重试。
extension _ShareReceiveProgressHistory on ShareTransferHistory {
  void _recordReceivedProgress(String? id, ShareCoreFileProgress progress) {
    final summary = _cache[id];
    if (summary == null ||
        summary.status != ShareTransferStatus.transferring ||
        progress.direction != 'receive' ||
        progress.index < 0 ||
        progress.index >= summary.fileCount ||
        progress.totalBytes < 1 ||
        progress.totalBytes > ShareCoreContract.maxFileBytes ||
        progress.bytes < 0 ||
        progress.bytes > progress.totalBytes) {
      return;
    }
    if (summary.fileCount == 1) {
      if (progress.totalBytes != summary.bytes ||
          progress.bytes < summary.transferredBytes) {
        return;
      }
      _update(
        summary.update(transferredBytes: progress.bytes, progressKnown: true),
      );
      return;
    }
    final files = _receiveFiles.putIfAbsent(summary.id, () => {});
    final previous = files[progress.index];
    if (previous != null &&
        (previous.bytes != progress.totalBytes ||
            previous.transferredBytes > progress.bytes)) {
      return;
    }
    final declared =
        files.values.fold<int>(0, (sum, file) => sum + file.bytes) -
        (previous?.bytes ?? 0) +
        progress.totalBytes;
    final knownCount = files.length + (previous == null ? 1 : 0);
    if (declared + summary.fileCount - knownCount > summary.bytes ||
        (knownCount == summary.fileCount && declared != summary.bytes)) {
      return;
    }
    files[progress.index] = ShareTransferRecord(
      id: '${summary.id}-${progress.index.toString().padLeft(3, '0')}',
      batchId: summary.id,
      fileIndex: progress.index,
      direction: ShareTransferDirection.receive,
      status: summary.status,
      deviceName: summary.deviceName,
      address: summary.address,
      fileName: '',
      bytes: progress.totalBytes,
      transferredBytes: progress.bytes,
      progressKnown: true,
      createdAt: summary.createdAt,
    );
    final observed = files.values.fold<int>(
      0,
      (sum, file) => sum + file.transferredBytes,
    );
    _update(
      summary.update(
        progressKnown: true,
        transferredBytes: observed > summary.transferredBytes
            ? observed
            : summary.transferredBytes,
      ),
    );
  }

  List<ShareTransferRecord> _receivedProgressRecords(
    ShareTransferRecord summary,
  ) => [
    summary,
    if (summary.fileCount > 1)
      for (final file
          in _receiveFiles[summary.id]?.values ?? const <ShareTransferRecord>[])
        file.update(
          status: summary.status,
          completedAt: summary.completedAt,
          error: summary.error,
        ),
  ];
}
