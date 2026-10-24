part of 'dlna_renderer_service.dart';

/// SSDP 发现只公布系统路由选中的网卡地址。
extension DlnaRendererDiscovery on DlnaRendererService {
  Future<InternetAddress?> _addressFor(InternetAddress destination) {
    final now = DateTime.now();
    _discoveryAddressCache.removeWhere(
      (_, entry) => entry.expires.isBefore(now),
    );
    final key = destination.address;
    final cached = _discoveryAddressCache[key];
    if (cached != null) return cached.address;
    if (_discoveryAddressCache.length >= 32) {
      _discoveryAddressCache.remove(_discoveryAddressCache.keys.first);
    }
    final address = _resolveAddress(destination);
    _discoveryAddressCache[key] = (
      address: address,
      expires: now.add(const Duration(seconds: 30)),
    );
    return address;
  }

  Future<InternetAddress?> _resolveAddress(InternetAddress destination) async {
    try {
      final route = await Process.run('/sbin/route', [
        '-n',
        'get',
        destination.address,
      ]).timeout(const Duration(seconds: 2));
      if (route.exitCode != 0) return null;
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final address = DlnaDiscoveryAddress.select(
        route.stdout as String,
        destination,
        {
          for (final interface in interfaces)
            interface.name: interface.addresses,
        },
      );
      debugPrint(
        '[DLNA] route to=${destination.address} location=${address?.address ?? 'none'}',
      );
      return address;
    } catch (error) {
      debugPrint('[DLNA] route lookup failed: $error');
      return null;
    }
  }

  void _handleSearch(Datagram packet) {
    final text = ascii.decode(packet.data, allowInvalid: true);
    if (!text.toUpperCase().startsWith('M-SEARCH * HTTP/1.1')) return;
    final st = RegExp(
      r'^ST:\s*(.+)$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(text)?.group(1)?.trim();
    if (st == null ||
        !['ssdp:all', ...DlnaProtocol.searchTargets].contains(st)) {
      return;
    }
    debugPrint('[DLNA] discovery from=${packet.address.address} st=$st');
    unawaited(_replySearch(packet.address, packet.port, st));
  }

  Future<void> _replySearch(
    InternetAddress destination,
    int port,
    String st,
  ) async {
    final socket = _ssdp;
    final server = _http;
    if (socket == null || server == null) return;
    final address = await _addressFor(destination);
    if (address == null) return;
    for (final target in st == 'ssdp:all' ? DlnaProtocol.searchTargets : [st]) {
      final usn = target.startsWith('uuid:')
          ? target
          : 'uuid:${DlnaProtocol.uuid}::$target';
      final message =
          'HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=300\r\nEXT:\r\nLOCATION: http://${address.address}:${server.port}/device.xml\r\nSERVER: macOS/1.0 UPnP/1.0 AnyDeck/1.0\r\nST: $target\r\nUSN: $usn\r\n\r\n';
      socket.send(ascii.encode(message), destination, port);
    }
  }

  Future<void> _advertise({required bool alive}) async {
    final socket = _ssdp;
    final server = _http;
    if (socket == null || server == null) return;
    final address = await _addressFor(DlnaRendererService._multicast);
    if (address == null) return;
    for (final target in DlnaProtocol.searchTargets) {
      final usn = target.startsWith('uuid:')
          ? target
          : 'uuid:${DlnaProtocol.uuid}::$target';
      final message =
          'NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nCACHE-CONTROL: max-age=300\r\nLOCATION: http://${address.address}:${server.port}/device.xml\r\nNT: $target\r\nNTS: ssdp:${alive ? 'alive' : 'byebye'}\r\nSERVER: macOS/1.0 UPnP/1.0 AnyDeck/1.0\r\nUSN: $usn\r\n\r\n';
      socket.send(ascii.encode(message), DlnaRendererService._multicast, 1900);
    }
  }
}
