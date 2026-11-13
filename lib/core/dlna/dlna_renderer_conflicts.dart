part of 'dlna_renderer_service.dart';

/// 复用 SSDP socket 处理运行中冲突，仅更新发现名称，不重建 HTTP 或播放器。
extension DlnaRendererConflicts on DlnaRendererService {
  void setNameConflictHandler(Future<void> Function(String, String) handler) {
    _onNameConflict = handler;
  }

  void _startNameMonitor() {
    final generation = ++_discoveryGeneration;
    _nameMonitor = DlnaNameConflictMonitor(
      uuid: _uuid,
      baseName: _baseServerName,
      currentName: () => _serverName,
      onConflict: (base, fallback) async {
        final nameGeneration = _nameGeneration;
        bool current() =>
            generation == _discoveryGeneration &&
            nameGeneration == _nameGeneration &&
            _baseServerName == base &&
            _http != null;
        if (!current()) return;
        try {
          final handler = _onNameConflict;
          if (handler != null) {
            await handler(base, fallback);
          } else {
            await ReceiverNames.recordPublishedConflict(
              await SharedPreferences.getInstance(),
              base,
              'DLNA',
              _uuid,
              fallback,
            );
          }
        } catch (error) {
          debugPrint('[DLNA] conflict persistence failed: $error');
        }
        if (current()) await _changePublishedName(fallback, nameGeneration);
      },
    );
  }

  void _startNameSearches() {
    final generation = _discoveryGeneration;
    unawaited(_searchNames(generation));
    for (final delay in [
      const Duration(seconds: 1),
      const Duration(seconds: 3),
    ]) {
      late final Timer timer;
      timer = Timer(delay, () {
        _nameSearchRetries.remove(timer);
        unawaited(_searchNames(generation));
      });
      _nameSearchRetries.add(timer);
    }
    _nameSearchTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(_searchNames(generation));
    });
  }

  Future<void> _searchNames(int generation) async {
    final socket = _ssdp;
    if (socket == null || generation != _discoveryGeneration) return;
    try {
      // 网卡切换后补加入新接口，保留既有 HTTP 连接和媒体会话。
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      if (generation != _discoveryGeneration) return;
      for (final interface in interfaces) {
        try {
          socket.joinMulticast(DlnaRendererService._multicast, interface);
        } catch (_) {}
      }
      _discoveryAddressCache.clear();
      const message =
          'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\n'
          'MX: 1\r\nST: ${DlnaProtocol.deviceType}\r\n\r\n';
      socket.send(ascii.encode(message), DlnaRendererService._multicast, 1900);
      await _advertise(alive: true);
    } catch (error) {
      debugPrint('[DLNA] conflict search failed: $error');
    }
  }

  void _stopNameMonitoring() {
    _discoveryGeneration++;
    _nameGeneration++;
    _nameSearchTimer?.cancel();
    _nameSearchTimer = null;
    for (final timer in _nameSearchRetries) {
      timer.cancel();
    }
    _nameSearchRetries.clear();
    _nameMonitor?.dispose();
    _nameMonitor = null;
  }

  /// 测试通过伪 SSDP 总线与真实 HTTP 描述复现并发启动，不绑定系统 1900 端口。
  @visibleForTesting
  Future<void> observeNameAnnouncement(ReceiverSsdpReply packet) async {
    final monitor = _nameMonitor;
    monitor?.observe(packet);
    await monitor?.idle;
  }
}
