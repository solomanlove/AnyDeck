part of 'airplay_server_service.dart';

/// AirPlay Server 服务状态 Notifier
class AirPlayServerNotifier extends Notifier<AirPlaySessionData?> {
  Timer? _timer;
  AirPlayVideoPlayer? _videoPlayer;
  final Map<int, String> _lastErrors = {};
  bool _spawningStandby = false;
  bool _disposed = false;
  static const int _initialClientSlots = 3;
  static const int _maxConcurrentSessions = 4;

  @override
  AirPlaySessionData? build() {
    AirPlaySessionData? latestSession;
    listenSelf((_, next) => latestSession = next);
    ref.listen(appSettingsProvider.select((s) => s.language), (_, next) {
      unawaited(_updateVideoLabels());
    });
    ref.onDispose(() {
      _disposed = true;
      unawaited(_videoPlayer?.stop());
      _timer?.cancel();
      final current = latestSession;
      if (current != null) {
        for (final s in current.allSessions) {
          unawaited(AirPlayServerService.instance.stop(s));
        }
      }
    });
    return null;
  }

  /// 开启投屏服务（仅主槽位发布单个 Bonjour 广播，附加槽位用于多设备并发解码渲染）
  Future<void> startServer({
    String name = 'AnyDeck-AirPlay',
    int rtspPort = 7000,
    int videoPort = 7100,
  }) async {
    await stopServer();
    final service = AirPlayServerService.instance;
    final primary = await service.start(
      name: name,
      rtspPort: rtspPort,
      videoPort: videoPort,
    );
    final standbySlots = <AirPlaySessionData>[];
    for (int i = 1; i < _initialClientSlots; i++) {
      try {
        final slot = await service.start(
          name: name,
          rtspPort: 0,
          videoPort: 0,
        );
        standbySlots.add(slot);
      } catch (e) {
        debugPrint('[AirPlay] Pre-allocated slot #$i skipped: $e');
      }
    }
    state = primary.copyWith(additionalSessions: standbySlots);
    // HTTP 视频不产生镜像首帧，需要独立驱动媒体播放器窗口。
    try {
      final bridge = AirPlayVideoBridge();
      _videoPlayer ??= AirPlayVideoPlayer(
        read: bridge.read,
        report: bridge.report,
        onActivityChanged: (active) {
          if (!_disposed && state != null) state = state!.copyWith(isVideoPlaying: active);
        },
      );
      await _videoPlayer!.start(primary.id, name);
      await _updateVideoLabels();
    } catch (error) {
      debugPrint('[AirPlay Video] unavailable (${error.runtimeType}); rebuild native library');
    }
    _lastErrors.clear();

    // 启动状态、客户端元数据与画面尺寸轮询
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      _pollAllSessions();
    });
  }

  void _pollAllSessions() {
    final current = state;
    if (current == null) return;
    final service = AirPlayServerService.instance;
    final all = current.allSessions;
    bool changed = false;
    final updatedList = <AirPlaySessionData>[];

    for (final session in all) {
      final error = service.getLastError(session.id);
      if (error != null && error != _lastErrors[session.id]) {
        _lastErrors[session.id] = error;
        debugPrint('[AirPlay] ERROR (${session.id}): $error');
      }
      final status = service.getStatus(session.id);
      final size = service.getDimensions(session.id);
      final client = service.getClientInfo(session.id);
      final isMirroring = status.isMirrorSession;

      final nextW = isMirroring ? (size?.width.toInt() ?? session.width) : 0;
      final nextH = isMirroring ? (size?.height.toInt() ?? session.height) : 0;
      final nextDevId = isMirroring
          ? (client?.deviceId ?? session.clientDeviceId)
          : client?.deviceId;
      final nextModel = isMirroring
          ? (client?.model ?? session.clientModel)
          : client?.model;
      final nextName = isMirroring
          ? (client?.name ?? session.clientName)
          : client?.name;

      if (status != session.status ||
          nextW != session.width ||
          nextH != session.height ||
          nextDevId != session.clientDeviceId ||
          nextModel != session.clientModel ||
          nextName != session.clientName) {
        if (status != session.status) {
          debugPrint('[AirPlay] session=${session.id} ${session.status.name} -> ${status.name} size=${nextW}x$nextH');
        }
        changed = true;
        updatedList.add(
          session.copyWith(
            status: status,
            width: nextW,
            height: nextH,
            clientDeviceId: nextDevId,
            clientModel: nextModel,
            clientName: nextName,
            clearClient: !isMirroring && client == null,
            additionalSessions: const [],
          ),
        );
      } else {
        updatedList.add(session.copyWith(additionalSessions: const []));
      }
    }

    if (changed && updatedList.isNotEmpty) {
      state = updatedList.first.copyWith(
        additionalSessions: updatedList.sublist(1),
      );
    }

    // 多台设备并发投屏支持：当所有已分配槽位均处于投屏状态时，自动补充一个无广播待机槽位
    final latest = state;
    if (latest != null &&
        !_spawningStandby &&
        latest.allSessions.length < _maxConcurrentSessions &&
        latest.allSessions.every((s) => s.status.isMirrorSession)) {
      _spawningStandby = true;
      final slot = latest.allSessions.length + 1;
      unawaited(_spawnStandbySession(slot));
    }
  }

  Future<void> _spawnStandbySession(int slot) async {
    try {
      final baseName = (state?.serverName.trim().isNotEmpty ?? false)
          ? state!.serverName.trim()
          : 'AnyDeck-AirPlay';
      final standby = await AirPlayServerService.instance.start(
        name: baseName,
        rtspPort: 0,
        videoPort: 0,
      );
      final current = state;
      if (current == null) {
        await AirPlayServerService.instance.stop(standby);
        return;
      }
      state = current.copyWith(
        additionalSessions: [...current.additionalSessions, standby],
      );
    } catch (e) {
      debugPrint('[AirPlay] Standby session #$slot spawn skipped: $e');
    } finally {
      _spawningStandby = false;
    }
  }

  /// 断开单台设备的 AirPlay 投屏会话（保持主广播接收器与其他正在投屏的设备继续运行）
  Future<void> stopSession(int sessionId) async {
    final current = state;
    if (current == null) return;
    final all = current.allSessions;
    final target = all.where((s) => s.id == sessionId).firstOrNull;
    if (target == null) return;

    await AirPlayServerService.instance.disconnect(sessionId);
    _lastErrors.remove(sessionId);

    final updated = all.map((s) {
      if (s.id == sessionId) {
        return s.copyWith(
          status: AirPlayServerStatus.idle,
          width: 0,
          height: 0,
          clearClient: true,
          additionalSessions: const [],
        );
      }
      return s.copyWith(additionalSessions: const []);
    }).toList();

    state = updated.first.copyWith(
      additionalSessions: updated.sublist(1),
    );
  }

  Future<void> showVideoWindow() async => _videoPlayer?.showWindow();

  Future<void> _updateVideoLabels() async {
    final player = _videoPlayer;
    if (player == null) return;
    final l10n = AppLocalizations(ref.read(appSettingsProvider).language.locale);
    try {
      await player.setLabels(
        title: '${state?.serverName ?? 'AirPlay'} · ${l10n.t('airplayVideoTitle')}',
        loading: l10n.t('dlnaLoading'),
        failure: l10n.t('airplayVideoFailed'),
        pin: l10n.t('pinAlwaysOnTop'),
        unpin: l10n.t('unpinAlwaysOnTop'),
      );
    } catch (_) {}
  }

  /// 停止全部投屏服务
  Future<void> stopServer() async {
    _timer?.cancel();
    _timer = null;
    await _videoPlayer?.stop();
    _lastErrors.clear();
    final current = state;
    if (current != null) {
      for (final s in current.allSessions) {
        await AirPlayServerService.instance.stop(s);
      }
      state = null;
    }
  }
}

/// AirPlay Server 服务全局状态 Provider
final airplaySessionProvider =
    NotifierProvider<AirPlayServerNotifier, AirPlaySessionData?>(
  AirPlayServerNotifier.new,
);
