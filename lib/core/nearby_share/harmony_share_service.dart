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
import 'harmony_share_outbox.dart';
import 'share_local_name.dart';

part 'harmony_share_receive_events.dart';
part 'harmony_share_send_service.dart';
part 'harmony_share_configuration.dart';

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
      _resolveLocalName = ShareLocalName.resolve,
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
    Future<String> Function()? resolveLocalName,
  }) : _client = client,
       _detectNetwork = detectNetwork,
       _downloads = downloads,
       _resolveLocalName = resolveLocalName ?? (() async => ShareLocalName.defaultName),
       _supported = true,
       _nativeBatch = nativeBatch {
    history?.addListener(notifyListeners);
  }
  static final instance = HarmonyShareService._();

  final ShareCoreClient _client;
  final Future<ShareNetwork> Function() _detectNetwork;
  final Future<Directory?> Function() _downloads;
  final Future<String> Function() _resolveLocalName;
  String _localName = ShareLocalName.defaultName;
  bool _configuring = false;
  String get localName => _localName;
  bool get configuring => _configuring;
  final bool _supported;
  final bool _nativeBatch;
  String? _receiveDirectory;
  ShareIncomingOffer? _batchOffer;
  ShareFileProgressLedger? _receiveProgress;
  bool _receiveAccepted = false;
  List<ShareCoreFileProgress> get receiveFileProgress => _receiveProgress?.snapshots ?? const [];
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
  Future<void>? _sending;
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
    sendBatch: _nativeBatch ? _sendNativeBatch : null,
    onBatchQueued: history?.queuedBatch,
    onBatchChanged: _batchChanged,
    cancelActive: _sender.cancel,
    onQueued: history?.queued,
    onChanged: history?.sentItemChanged,
  )..addListener(notifyListeners);

  late final outbox = HarmonyShareOutbox(
    persist: (batch) async => history?.queuedBatch(batch),
    execute: (batch) async {
      await sendQueue.runPrepared(batch);
      return sendQueue.batch;
    },
    cancelActive: sendQueue.cancelAll,
    changed: (batch) => history?.sentBatchChanged(batch),
  )..addListener(notifyListeners);
  bool get canAppend => _nativeBatch && busy && !receiving && outbox.accepting;
  bool get canSelectFiles => !_configuring && (!busy || canAppend);

  /// 主窗口预留设置写入边界，防止保存期间启动新收发会话。
  Future<void> configureLocalName(String value, Future<void> Function() save) =>
      _configureLocalName(value, save);

  Future<void> send(ShareCorePeer peer, File file) => sendFiles(peer, [file]);

  Future<void> sendFiles(ShareCorePeer peer, List<File> files) =>
      _runBatch(peer, () => ShareSendSelection.inspect(files));

  /// UI 确认过的元数据保持不变，队列开始每项前再检查文件是否被修改。
  Future<void> sendSelection(
    ShareCorePeer peer,
    ShareSendSelection selection, {
    String? retryOf,
  }) => _runBatch(peer, () async => selection, retryOf: retryOf);

  /// 只将已确认选择加入待发队列，返回表示已提交排队，不表示发送成功。
  Future<void> appendSelection(
    ShareCorePeer peer,
    ShareSendSelection selection, {
    String? retryOf,
  }) => _appendSelection(peer, selection, retryOf: retryOf);

  bool get enabled => _enabled;
  /// 仅实际接收/发现窗口存活且空闲时显示扫描动画，发送期间不伪装仍在扫描。
  bool get scanning => _enabled && !busy && !_configuring && _receiver != null && error == null;

  Future<void> start() async {
    if (_enabled || !_supported) return;
    _enabled = true;
    // 新一轮启用必须重新发现，不能沿用已结束窗口的设备。
    peers.clear();
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
    if (_refreshing || _configuring) return;
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
    outbox.cancelAll();
    sendQueue.cancelAll();
    await _stopWindow();
    await _sending;
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
    if (!_enabled || busy || _configuring || _receiver != null || _closingWindows > 0) return;
    final revision = _windowRevision;
    try {
      final localName = await _resolveLocalName();
      ShareLocalName.validate(localName);
      _localName = localName;
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
        localName: localName,
      ) : _client.startInteractiveReceiver(localAddress: network!.local,
        broadcastAddress: network!.broadcast, outputDirectory: folder));
      if (!_enabled || busy || _configuring || revision != _windowRevision) {
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
          // 主动停止时仍排空历史事件，但不污染下一轮操作的错误提示。
          if (_closingWindows == 0) error = '$failure';
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
          _receiveProgress = null;
          _receiveAccepted = false;
          pendingOffer = null;
          if (receiving) {
            receiving = false;
            busy = false;
            progress = null;
          }
          final rediscover = _enabled && !busy && _closingWindows == 0;
          // 自然结束后设备可见性失效；发送暂停接收时保留当前目标。
          if (rediscover) peers.clear();
          notifyListeners();
          if (rediscover) {
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
    _receiveAccepted = accept;
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
    _receiveAccepted = false;
    history?.receiveChanged(
      _incomingHistoryId,
      status: ShareTransferStatus.timedOut,
    );
    pendingOffer = null;
    _receiver?.decide(false);
    notifyListeners();
  }

  void cancelTransfer() {
    if (receiving && _sending == null) {
      unawaited(_cancelReceiving());
    } else {
      _sendCancelled = true;
      outbox.cancelAll();
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
      // stop 排空期间可能迟到 session_started，再次清理它创建的 watchdog。
      _windowTimer?.cancel();
      _windowTimer = null;
      _events = null;
      _receiver = null;
      _incomingHistoryId = null;
      _receiveProgress = null;
      _receiveAccepted = false;
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
          _sending == null &&
          _receiver == null) {
        unawaited(_startWindow());
      }
    }
  }

  @override
  void dispose() {
    history?.removeListener(notifyListeners);
    outbox.removeListener(notifyListeners);
    outbox.dispose();
    sendQueue.removeListener(notifyListeners);
    sendQueue.dispose();
    super.dispose();
  }
}
