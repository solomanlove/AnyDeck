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
  HarmonyShareService._();
  static final instance = HarmonyShareService._();

  final ShareCoreClient _client = const ShareCoreClient();
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
  bool _refreshing = false;
  bool _enabled = false;
  bool busy = false;
  String? error;

  bool get enabled => _enabled;

  Future<void> start() async {
    if (_enabled || !Platform.isMacOS) return;
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
        final current = await ShareNetwork.detect();
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
    await _stopWindow();
    notifyListeners();
  }

  Future<void> _startWindow() async {
    if (!_enabled || busy) return;
    try {
      network = await ShareNetwork.detect();
      final downloads = await getDownloadsDirectory();
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
      if (!_enabled) {
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
            case 'incoming_offer':
              final address = InternetAddress.tryParse('${event['ip']}');
              final bytes = event['bytes'];
              if (address != null &&
                  bytes is int &&
                  bytes > 0 &&
                  bytes <= 1024 * 1024) {
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
    await _stopWindow();
    notifyListeners();
    try {
      final currentNetwork = await ShareNetwork.detect();
      final transfer = await _client.sendFileForTest(
        localAddress: currentNetwork.local,
        peer: peer,
        file: file,
      );
      _transfer = transfer;
      final result = await transfer.result;
      if (result['event'] == 'file_sent') recent.insert(0, file.path);
      if (recent.length > 50) recent.removeRange(50, recent.length);
      unawaited(_saveRecent());
      error = null;
    } catch (failure) {
      error = '$failure';
    } finally {
      _transfer = null;
      busy = false;
      notifyListeners();
      if (_enabled) await _startWindow();
    }
  }

  void cancelTransfer() => _transfer?.cancel();

  Future<void> _saveRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentKey, recent);
    } catch (_) {
      // 传输结果不依赖本地记录写入。
    }
  }

  Future<void> _stopWindow() async {
    _windowTimer?.cancel();
    _windowTimer = null;
    await _events?.cancel();
    _events = null;
    await _receiver?.stop();
    _receiver = null;
    pendingOffer = null;
  }
}
