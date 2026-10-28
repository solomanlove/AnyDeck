import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'share_core_client.dart';
import 'share_network.dart';

/// 展示给用户的来件摘要；协议内容不进入主仓库。
class ShareIncomingOffer {
  const ShareIncomingOffer(this.address, this.bytes);
  final InternetAddress address;
  final int bytes;
}

/// 主窗口唯一收发服务；页面切换不停止监听。
class HarmonyShareService extends ChangeNotifier {
  HarmonyShareService._()
    : _client = const ShareCoreClient(),
      _detectNetwork = ShareNetwork.detect,
      _downloads = getDownloadsDirectory,
      _supported = Platform.isMacOS;

  /// 离线生命周期测试注入边界，不访问真实网络或启动核心。
  @visibleForTesting
  HarmonyShareService.testing({
    required ShareCoreClient client,
    required Future<ShareNetwork> Function() detectNetwork,
    required Future<Directory?> Function() downloads,
  }) : _client = client,
       _detectNetwork = detectNetwork,
       _downloads = downloads,
       _supported = true;
  static final instance = HarmonyShareService._();

  final ShareCoreClient _client;
  final Future<ShareNetwork> Function() _detectNetwork;
  final Future<Directory?> Function() _downloads;
  final bool _supported;
  final Map<String, ShareCorePeer> peers = {};
  final List<String> recent = [];
  static const _recentKey = 'harmony_share_recent_paths';
  ShareIncomingOffer? pendingOffer;
  ShareNetwork? network;
  ShareCoreReceiveSession? _receiver;
  StreamSubscription<Map<String, dynamic>>? _events;
  ShareCoreTransfer? _transfer;
  Timer? _networkTimer;
  Timer? _windowTimer;
  Future<void>? _startingWindow;
  int _windowRevision = 0;
  bool _refreshing = false;
  bool _sendCancelled = false;
  bool _enabled = false;
  bool busy = false;
  bool receiving = false;
  ShareCoreProgress? progress;
  StreamSubscription<ShareCoreProgress>? _progressEvents;
  String? activeFile;
  String? error;

  bool get enabled => _enabled;

  Future<void> start() async {
    if (_enabled || !_supported) return;
    _enabled = true;
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
    _transfer?.cancel();
    await _stopWindow();
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
    if (!_enabled || busy || _receiver != null) return;
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
      final receiver = await _client.startInteractiveReceiver(
        localAddress: network!.local,
        broadcastAddress: network!.broadcast,
        outputDirectory: folder,
      );
      if (!_enabled || busy || revision != _windowRevision) {
        await receiver.stop();
        return;
      }
      _receiver = receiver;
      _windowTimer?.cancel();
      _windowTimer = Timer(const Duration(seconds: 125), () {
        if (_enabled && _receiver == receiver && !busy) {
          unawaited(refresh());
        }
      });
      error = null;
      notifyListeners();
      _events = receiver.events.listen(
        (event) {
          switch (event['event']) {
            case 'device':
              try {
                final peer = ShareCorePeer.parse(event);
                peers[peer.address.address] = peer;
                notifyListeners();
              } catch (_) {
                /* 忽略不可信发现报文。 */
              }
            case 'session_started':
              receiving = true;
              busy = true;
              progress = null;
              _windowTimer?.cancel();
              _windowTimer = Timer(
                ShareCoreContract.transferTimeout + const Duration(minutes: 3),
                cancelTransfer,
              );
              notifyListeners();
            case 'progress':
              try {
                final update = ShareCoreProgress.parse(event);
                if (update.direction == 'receive' &&
                    (progress == null || update.bytes >= progress!.bytes)) {
                  progress = update;
                  notifyListeners();
                }
              } on FormatException {
                // 无效进度不推进状态，最终文件仍由核心校验。
              }
            case 'incoming_offer':
              final address = InternetAddress.tryParse('${event['ip']}');
              final bytes = event['bytes'];
              if (address != null &&
                  bytes is int &&
                  bytes > 0 &&
                  bytes <= ShareCoreContract.maxFileBytes) {
                pendingOffer = ShareIncomingOffer(address, bytes);
                notifyListeners();
              } else {
                receiver.decide(false);
              }
            case 'file_received':
              final path = event['path'];
              if (path is String) recent.insert(0, path);
              if (recent.length > 50) recent.removeRange(50, recent.length);
              unawaited(_saveRecent());
              pendingOffer = null;
              notifyListeners();
            case 'error':
              if (event['reason'] != 'deadline') {
                error = '${event['code']}: ${event['reason'] ?? ''}';
              }
              pendingOffer = null;
              notifyListeners();
          }
        },
        onError: (Object failure) {
          error = '$failure';
          pendingOffer = null;
          notifyListeners();
        },
        onDone: () {
          if (_receiver != receiver) return;
          _windowTimer?.cancel();
          _windowTimer = null;
          _receiver = null;
          pendingOffer = null;
          if (receiving) {
            receiving = false;
            busy = false;
            progress = null;
          }
          notifyListeners();
          if (_enabled && !busy) {
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
    pendingOffer = null;
    _receiver?.decide(accept);
    notifyListeners();
  }

  Future<void> send(ShareCorePeer peer, File file) async {
    if (busy) return;
    busy = true;
    _sendCancelled = false;
    activeFile = file.uri.pathSegments.last;
    progress = null;
    notifyListeners();
    try {
      await _stopWindow();
      if (_sendCancelled) throw StateError('Transfer cancelled');
      final currentNetwork = await _detectNetwork();
      if (_sendCancelled) throw StateError('Transfer cancelled');
      final transfer = await _client.sendFileForTest(
        localAddress: currentNetwork.local,
        peer: peer,
        file: file,
      );
      _transfer = transfer;
      if (_sendCancelled) transfer.cancel();
      _progressEvents = transfer.progress.listen((update) {
        if (update.direction == 'send' &&
            (progress == null || update.bytes >= progress!.bytes)) {
          progress = update;
          notifyListeners();
        }
      });
      final result = await transfer.result;
      if (result['event'] == 'file_sent') recent.insert(0, file.path);
      if (recent.length > 50) recent.removeRange(50, recent.length);
      unawaited(_saveRecent());
      error = null;
    } catch (failure) {
      error = '$failure';
    } finally {
      await _progressEvents?.cancel();
      _progressEvents = null;
      _transfer = null;
      activeFile = null;
      progress = null;
      busy = false;
      notifyListeners();
      if (_enabled) await _startWindow();
    }
  }

  void cancelTransfer() {
    if (receiving) {
      unawaited(_cancelReceiving());
    } else {
      _sendCancelled = true;
      _transfer?.cancel();
    }
  }

  Future<void> _cancelReceiving() async {
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
    _windowRevision++;
    await _startingWindow;
    _windowTimer?.cancel();
    _windowTimer = null;
    await _events?.cancel();
    _events = null;
    await _receiver?.stop();
    _receiver = null;
    pendingOffer = null;
    if (receiving) {
      receiving = false;
      busy = false;
      progress = null;
    }
  }
}
