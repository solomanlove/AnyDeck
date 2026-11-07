part of 'harmony_share_service.dart';

/// 接收事件与完整批次验证集中处理；页面不持有原生会话。
extension _HarmonyShareReceiveEvents on HarmonyShareService {
  void _handleReceiverEvent(
    Map<String, dynamic> event,
    ShareCoreReceiveSession receiver,
  ) {
    if (_configuring) return;
    switch (event['event']) {
      case 'discovery_ready':
        if (!_enabled || _closingWindows > 0 || _receiver != receiver || busy) return;
        _clearDiscoveryStartup();
        _discoveryReady = true;
        error = null;
        _changed();
      case 'device':
        try {
          final peer = ShareCorePeer.parse(event);
          peers[peer.address.address] = peer;
          _changed();
        } catch (_) {
          /* 忽略不可信发现报文。 */
        }
      case 'session_started':
        _clearDiscoveryStartup();
        _discoveryReady = false;
        _batchOffer = null;
        _receiveProgress = null;
        _receiveAccepted = false;
        _incomingHistoryId = null;
        receiving = true;
        busy = true;
        progress = null;
        _windowTimer?.cancel();
        _windowTimer = Timer(
          ShareCoreContract.transferTimeout + const Duration(minutes: 3),
          cancelTransfer,
        );
        _changed();
      case 'progress':
        try {
          final update = ShareCoreProgress.parse(
            event,
            maxTotalBytes: _batchOffer == null
                ? ShareCoreContract.maxFileBytes
                : ShareBatchContract.maxBytes,
          );
          if (update.direction == 'receive' &&
              (_batchOffer == null || update.totalBytes == _batchOffer!.bytes) &&
              (progress == null || update.bytes >= progress!.bytes)) {
            progress = update;
            history?.receiveChanged(
              _incomingHistoryId,
              transferredBytes: update.bytes,
            );
            _changed();
          }
        } on FormatException {
          // 无效进度不推进状态，最终文件仍由核心校验。
        }
      case 'incoming_batch':
      case 'incoming_offer':
        final address = InternetAddress.tryParse('${event['ip']}');
        final bytes = event['event'] == 'incoming_batch'
            ? event['total_bytes']
            : event['bytes'];
        final count = event['event'] == 'incoming_batch'
            ? event['file_count']
            : 1;
        if (address != null &&
            bytes is int &&
            bytes > 0 &&
            count is int &&
            count >= 1 &&
            count <= ShareBatchContract.maxFiles &&
            bytes >= count &&
            bytes <= ShareBatchContract.maxBytes) {
          try {
            // 先预留记录清单容量，存储积压时在用户接受之前拒绝新来件。
            _incomingHistoryId = history?.incoming(
              address: address.address,
              name: peers[address.address]?.name ?? address.address,
              bytes: bytes,
              fileCount: count,
            );
            pendingOffer = ShareIncomingOffer(address, bytes, fileCount: count);
            _batchOffer = pendingOffer;
            _receiveProgress = ShareFileProgressLedger(count: count, bytes: bytes, direction: 'receive');
            _receiveAccepted = false;
          } catch (failure) {
            error = '$failure';
            pendingOffer = null;
            receiver.decide(false);
          }
          _changed();
        } else {
          receiver.decide(false);
        }
      case 'file_progress':
        if (!_receiveAccepted || !receiving || _receiveProgress == null) return;
        try {
          final update = _receiveProgress!.accept(event);
          history?.receivedFileProgress(_incomingHistoryId, update);
          _changed();
        } on FormatException {
          // Session 已校验；额外防止注入边界/迟到回调破坏服务展示。
        }
      case 'batch_received':
        try {
          final offer = _batchOffer;
          final directory = _receiveDirectory;
          if (offer == null || directory == null || event['files'] is! List) {
            throw const FormatException('Missing batch context');
          }
          final result = ShareBatchReceived(
            count: offer.fileCount,
            bytes: offer.bytes,
            directory: directory,
          );
          final rawFiles = event['files'] as List;
          for (var index = 0; index < rawFiles.length; index++) {
            result.add({
              'event': 'batch_file_received',
              'index': index,
              ...Map<String, dynamic>.from(rawFiles[index] as Map),
            });
          }
          final files = result.finish(event);
          if (history?.receivedBatch(_incomingHistoryId, files, directory) ??
              true) {
            recent.insertAll(0, files.map((file) => file['path'] as String));
            if (recent.length > 50) recent.removeRange(50, recent.length);
            unawaited(_saveRecent());
          }
          pendingOffer = null;
          _changed();
        } catch (failure) {
          error = '$failure';
          history?.receiveChanged(
            _incomingHistoryId,
            status: ShareTransferStatus.failed,
            error: '$failure',
          );
          pendingOffer = null;
          receiver.decide(false);
          _changed();
        }
      case 'file_received':
        final path = event['path'];
        if (path is String) {
          recent.insert(0, path);
          history?.receiveChanged(
            _incomingHistoryId,
            status: ShareTransferStatus.succeeded,
            fileName: File(path).uri.pathSegments.last,
            path: path,
            transferredBytes: event['bytes'] is int
                ? event['bytes'] as int
                : progress?.totalBytes,
            sha256: event['sha256'] is String
                ? event['sha256'] as String
                : null,
          );
        }
        if (recent.length > 50) recent.removeRange(50, recent.length);
        unawaited(_saveRecent());
        pendingOffer = null;
        _changed();
      case 'error':
        _clearDiscoveryStartup();
        _discoveryReady = false;
        history?.receiveChanged(
          _incomingHistoryId,
          status: event['reason'] == 'decision_timeout'
              ? ShareTransferStatus.timedOut
              : ShareTransferStatus.failed,
          error: '${event['code']}: ${event['reason'] ?? ''}',
        );
        if (_closingWindows == 0 && event['reason'] != 'deadline') {
          error = '${event['code']}: ${event['reason'] ?? ''}';
        }
        pendingOffer = null;
        _changed();
    }
  }
}
