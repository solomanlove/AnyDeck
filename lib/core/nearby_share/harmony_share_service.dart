import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'share_core_client.dart';
import 'share_network.dart';
import 'harmony_share_send_queue.dart';
import 'share_send_selection.dart';
import 'share_transfer_history.dart';
import 'share_transfer_record.dart';
import 'harmony_share_sender.dart';
import 'share_receive_directory.dart';

part 'harmony_share_receive_events.dart';

/// 展示给用户的来件摘要；协议内容不进入主仓库。
class ShareIncomingOffer {
  const ShareIncomingOffer(this.address, this.bytes, {this.fileCount = 1});
  final int fileCount;
  final InternetAddress address;
  final int bytes;
}

/// 主窗口唯一收发服务；页面切换不停止监听。
class HarmonyShareService extends ChangeNotifier {
  HarmonyShareService._()
    : _client = const ShareCoreClient(),
      _detectNetwork = ShareNetwork.detect,
      _downloads = ShareReceiveDirectory.resolve,
      _supported = Platform.isMacOS,
      _nativeBatch = true,
      history = ShareTransferHistory() {
    history!.addListener(notifyListeners);
  }

  /// 离线生命周期测试注入边界，不访问真实网络或启动核心。
  @visibleForTesting
  HarmonyShareService.testing({
    required ShareCoreClient client,
    required Future<ShareNetwork> Function() detectNetwork,
    required Future<Directory?> Function() downloads,
    this.history,
    bool nativeBatch = false,
  }) : _client = client,
       _detectNetwork = detectNetwork,
       _downloads = downloads,
       _supported = true,
       _nativeBatch = nativeBatch {
    history?.addListener(notifyListeners);
  }
  static final instance = HarmonyShareService._();

  final ShareCoreClient _client;
  final Future<ShareNetwork> Function() _detectNetwork;
  final Future<Directory?> Function() _downloads;
  final bool _supported;
  final bool _nativeBatch;
  String? _receiveDirectory;
  ShareIncomingOffer? _batchOffer;
  void _changed() => notifyListeners();
  final ShareTransferHistory? history;
  String? _incomingHistoryId;
  final Map<String, ShareCorePeer> peers = {};
  final List<String> recent = [];
  static const _recentKey = 'harmony_share_recent_paths';
  ShareIncomingOffer? pendingOffer;
  ShareNetwork? network;
  ShareCoreReceiveSession? _receiver;
  StreamSubscription<Map<String, dynamic>>? _events;
  Timer? _networkTimer;
  Timer? _windowTimer;
  Future<void>? _startingWindow;
  int _windowRevision = 0;
  int _closingWindows = 0;
  bool _refreshing = false;
  bool _sendCancelled = false;
  bool _enabled = false;
  bool busy = false;
  bool receiving = false;
  ShareCoreProgress? progress;
  String? activeFile;
  String? error;

  late final _sender = HarmonyShareSender(
    client: _client,
    detectNetwork: _detectNetwork,
  );

  late final sendQueue = HarmonyShareSendQueue(
    send: _sendOne,
    cancelActive: _sender.cancel,
    onQueued: history?.queued,
    onChanged: history?.sentItemChanged,
  )..addListener(notifyListeners);

  bool get enabled => _enabled;

  Future<void> start() async {
    if (_enabled || !_supported) return;
    _enabled = true;
    await history?.initialize();
    if (!_enabled) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      recent
        ..clear()
        ..addAll(prefs.getStringList(_recentKey) ?? const []);
    } catch (_) {
      // 本地记录读取失败不阻断发现与接收。
    }
    if (!_enabled) return;
    _networkTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_enabled || busy || _refreshing) return;
      try {
        final current = await _detectNetwork();
        if (network?.local != current.local ||
            network?.broadcast != current.broadcast ||
            _receiver == null) {
          await refresh();
        }
      } catch (_) {
        // 网络暂时不可用，下一轮继续检查。
      }
    });
    notifyListeners();
    await _startWindow();
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await _stopWindow();
      peers.clear();
      notifyListeners();
      if (_enabled) await _startWindow();
    } finally {
      _refreshing = false;
    }
  }

  Future<void> stop() async {
    _enabled = false;
    _networkTimer?.cancel();
    _networkTimer = null;
    _sendCancelled = true;
    sendQueue.cancelAll();
    await _stopWindow();
    await history?.flush();
    notifyListeners();
  }

  Future<void> _startWindow() async {
    if (_startingWindow != null) return _startingWindow;
    final starting = _openWindow();
    _startingWindow = starting;
    try {
      await starting;
    } finally {
      if (identical(_startingWindow, starting)) _startingWindow = null;
    }
  }

  /// 同一时间仅创建一轮接收器；stop/send 会使尚未完成的启动失效。
  Future<void> _openWindow() async {
    if (!_enabled || busy || _receiver != null || _closingWindows > 0) return;
    final revision = _windowRevision;
    try {
      network = await _detectNetwork();
      final downloads = await _downloads();
      if (downloads == null) {
        throw const FileSystemException('Downloads unavailable');
      }
      final folder = Directory(
        '${downloads.path}/AnyDeck-Share-'
        '${DateTime.now().microsecondsSinceEpoch}',
      );
      final receiver = await (_nativeBatch ? _client.startBatchReceiver(
        localAddress: network!.local,
        broadcastAddress: network!.broadcast,
        outputDirectory: folder,
      ) : _client.startInteractiveReceiver(localAddress: network!.local,
        broadcastAddress: network!.broadcast, outputDirectory: folder));
      if (!_enabled || busy || revision != _windowRevision) {
        await receiver.stop();
        return;
      }
      _receiver = receiver;
      _receiveDirectory = folder.path;
      _windowTimer?.cancel();
      _windowTimer = Timer(const Duration(seconds: 125), () {
        if (_enabled && _receiver == receiver && !busy) {
          unawaited(refresh());
        }
      });
      error = null;
      notifyListeners();
      _events = receiver.events.listen(
        (event) => _handleReceiverEvent(event, receiver),
        onError: (Object failure) {
          error = '$failure';
          history?.receiveChanged(
            _incomingHistoryId,
            status: ShareTransferStatus.failed,
            error: '$failure',
          );
          pendingOffer = null;
          notifyListeners();
        },
        onDone: () {
          if (_receiver != receiver) return;
          _windowTimer?.cancel();
          _windowTimer = null;
          _receiver = null;
          history?.receiveChanged(
            _incomingHistoryId,
            status: ShareTransferStatus.interrupted,
          );
          _incomingHistoryId = null;
          _batchOffer = null;
          pendingOffer = null;
          if (receiving) {
            receiving = false;
            busy = false;
            progress = null;
          }
          notifyListeners();
          if (_enabled && !busy && _closingWindows == 0) {
            Future<void>.delayed(const Duration(seconds: 1), _startWindow);
          }
        },
      );
    } catch (failure) {
      error = '$failure';
      notifyListeners();
    }
  }

  void decide(bool accept) {
    if (pendingOffer == null) return;
    history?.receiveChanged(
      _incomingHistoryId,
      status: accept
          ? ShareTransferStatus.transferring
          : ShareTransferStatus.rejected,
    );
    pendingOffer = null;
    _receiver?.decide(accept);
    notifyListeners();
  }

  /// UI 与核心都限制确认期限；超时与用户主动拒绝分别记录。
  void expireOffer(ShareIncomingOffer offer) {
    if (pendingOffer != offer) return;
    history?.receiveChanged(
      _incomingHistoryId,
      status: ShareTransferStatus.timedOut,
    );
    pendingOffer = null;
    _receiver?.decide(false);
    notifyListeners();
  }

  Future<void> send(ShareCorePeer peer, File file) => sendFiles(peer, [file]);

  Future<void> sendFiles(ShareCorePeer peer, List<File> files) =>
      _runBatch(peer, () => ShareSendSelection.inspect(files));

  /// UI 确认过的元数据保持不变，队列开始每项前再检查文件是否被修改。
  Future<void> sendSelection(
    ShareCorePeer peer,
    ShareSendSelection selection, {
    String? retryOf,
  }) => _runBatch(peer, () async => selection, retryOf: retryOf);

  Future<void> _runBatch(
    ShareCorePeer peer,
    Future<ShareSendSelection> Function() prepare, {
    String? retryOf,
  }) async {
    if (busy) return;
    busy = true;
    _sendCancelled = false;
    error = null;
    sendQueue.clear();
    notifyListeners();
    try {
      await _stopWindow();
      if (_sendCancelled) throw StateError('Transfer cancelled');
      final selection = await prepare();
      if (_sendCancelled) throw StateError('Transfer cancelled');
      await sendQueue.run(peer, selection, retryOf: retryOf);
      await history?.flush();
      final failures = sendQueue.items.where(
        (item) => item.status == ShareSendStatus.failed,
      );
      error = failures.isEmpty ? null : failures.first.error;
    } catch (failure) {
      error = '$failure';
    } finally {
      activeFile = null;
      progress = null;
      busy = false;
      notifyListeners();
      if (_enabled) await _startWindow();
    }
  }

  /// 每项只占用一个核心会话；整个 batch 结束后才恢复接收监听。
  Future<void> _sendOne(
    ShareSendItem item,
    ValueChanged<ShareCoreProgress> onProgress,
  ) async {
    activeFile = item.file.name;
    progress = null;
    await _sender.send(
      item,
      cancelled: () => _sendCancelled || sendQueue.isCancelled(item.id),
      onProgress: (update) {
        progress = update;
        onProgress(update);
      },
    );
    recent.insert(0, item.file.file.path);
    if (recent.length > 50) recent.removeRange(50, recent.length);
    unawaited(_saveRecent());
  }

  void cancelTransfer() {
    if (receiving) {
      unawaited(_cancelReceiving());
    } else {
      _sendCancelled = true;
      sendQueue.cancelAll();
    }
  }

  Future<void> _cancelReceiving() async {
    history?.receiveChanged(
      _incomingHistoryId,
      status: ShareTransferStatus.cancelled,
    );
    await _stopWindow();
    receiving = false;
    busy = false;
    progress = null;
    notifyListeners();
    if (_enabled) await _startWindow();
  }

  Future<void> _saveRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentKey, recent);
    } catch (_) {
      // 传输结果不依赖本地记录写入。
    }
  }

  Future<void> _stopWindow() async {
    _closingWindows++;
    _windowRevision++;
    history?.receiveChanged(
      _incomingHistoryId,
      status: ShareTransferStatus.interrupted,
    );
    try {
      await _startingWindow;
      _windowTimer?.cancel();
      _windowTimer = null;
      await _receiver?.stop();
      await _events?.cancel();
      _events = null;
      _receiver = null;
      _incomingHistoryId = null;
      pendingOffer = null;
      if (receiving) {
        receiving = false;
        busy = false;
        progress = null;
      }
    } finally {
      _closingWindows--;
      if (_closingWindows == 0 &&
          _enabled &&
          !busy &&
          !_refreshing &&
          _receiver == null) {
        unawaited(_startWindow());
      }
    }
  }

  @override
  void dispose() {
    history?.removeListener(notifyListeners);
    sendQueue.removeListener(notifyListeners);
    sendQueue.dispose();
    super.dispose();
  }
}
