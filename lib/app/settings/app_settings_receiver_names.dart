part of 'app_settings_controller.dart';

/// 身份读取和网络探测独立注入，测试无需读取真实电脑名称或扫描局域网。
final receiverIdentityProvider = FutureProvider<ReceiverIdentity>(
  (ref) => ReceiverIdentity.load(),
);
final receiverNameProbeProvider = Provider<ReceiverNameProbe>(
  (ref) => ReceiverNameProbe(),
);

/// 接收端默认名、原始自定义名和实际广播名分离；仅主窗口写入身份及设置。
mixin ReceiverNameSettings on Notifier<AppSettings>, SettingsBroadcast {
  Future<void>? _settingsLoaded;
  Future<void>? _receiverNamesLoading;

  Future<void> ensureReceiverNames() async {
    await _settingsLoaded;
    if (!ref.mounted) return;
    try {
      await (_receiverNamesLoading ??= _initializeReceiverNames());
    } catch (_) {
      _receiverNamesLoading = null;
      rethrow;
    }
  }

  Future<void> _initializeReceiverNames() async {
    if (ref.read(windowIdProvider).isNotEmpty) {
      final snapshot = await AppSettingsController._mainSettingsChannel
          .invokeMethod<Map>('resolve_receiver_names');
      if (ref.mounted && snapshot != null) {
        _applyReceiverNamesSnapshot(snapshot);
      }
      return;
    }
    final identity = await ref.read(receiverIdentityProvider.future);
    if (!ref.mounted) return;
    await _reloadReceiverNames(identity);
  }

  Future<void> _reloadReceiverNames(ReceiverIdentity identity) async {
    final prefs = await SharedPreferences.getInstance();
    final names = await ReceiverNames.load(prefs, identity);
    if (!ref.mounted) return;
    state = state.copyWith(
      airplayServerName: names.airplay,
      dlnaServerName: names.dlna,
      defaultAirplayReceiverName: names.defaultAirplay,
      defaultDlnaReceiverName: names.defaultDlna,
    );
    if (!DlnaRendererService.instance.isRunning) {
      await DlnaRendererService.instance.setServerName(names.dlna);
    }
  }

  Map<String, String> _receiverNamesSnapshot() => {
    'airplay': state.airplayServerName,
    'dlna': state.dlnaServerName,
    'defaultAirplay': state.defaultAirplayReceiverName,
    'defaultDlna': state.defaultDlnaReceiverName,
  };

  void _applyReceiverNamesSnapshot(Map snapshot) {
    state = state.copyWith(
      airplayServerName: snapshot['airplay'] as String,
      dlnaServerName: snapshot['dlna'] as String,
      defaultAirplayReceiverName: snapshot['defaultAirplay'] as String,
      defaultDlnaReceiverName: snapshot['defaultDlna'] as String,
    );
  }

  Future<void> setAirplayServerName(String value, {bool broadcast = true}) =>
      _setReceiverName('AirPlay', value, broadcast: broadcast);

  Future<void> setDlnaServerName(String value, {bool broadcast = true}) =>
      _setReceiverName('DLNA', value, broadcast: broadcast);

  Future<void> _setReceiverName(
    String protocol,
    String value, {
    bool broadcast = true,
  }) async {
    await ensureReceiverNames();
    if (!ref.mounted) return;
    if (!broadcast) {
      state = protocol == 'AirPlay'
          ? state.copyWith(airplayServerName: value)
          : state.copyWith(dlnaServerName: value);
      return;
    }
    if (ref.read(windowIdProvider).isNotEmpty) {
      final snapshot = await AppSettingsController._mainSettingsChannel
          .invokeMethod<Map>('change_receiver_name', {
            'protocol': protocol,
            'value': value,
          });
      if (ref.mounted && snapshot != null) {
        _applyReceiverNamesSnapshot(snapshot);
      }
      return;
    }
    final fallback = protocol == 'AirPlay'
        ? state.defaultAirplayReceiverName
        : state.defaultDlnaReceiverName;
    final clean = value.trim().isEmpty ? fallback : value.trim();
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(ReceiverNames.nameKey(protocol), clean)) {
      throw StateError('Cannot persist AnyDeck receiver name');
    }
    if (!ref.mounted) return;
    state = protocol == 'AirPlay'
        ? state.copyWith(airplayServerName: clean)
        : state.copyWith(dlnaServerName: clean);
    if (protocol == 'DLNA') {
      final service = DlnaRendererService.instance;
      await service.setServerName(
        service.isRunning
            ? await receiverNameForStart(
                protocol,
                alreadyRunning: service.serverName == clean,
              )
            : clean,
      );
    }
    await _broadcastReceiverNames();
  }

  /// 启动前有限时探测；重名时保留原始自定义设置，只调整广播名称。
  Future<String> receiverNameForStart(
    String protocol, {
    bool alreadyRunning = false,
  }) async {
    await ensureReceiverNames();
    final identity = await ref.read(receiverIdentityProvider.future);
    final prefs = await SharedPreferences.getInstance();
    final name = protocol == 'AirPlay'
        ? state.airplayServerName
        : state.dlnaServerName;
    if (ReceiverNames.disambiguate(name, protocol, identity.shortCode) ==
        name) {
      return name;
    }
    var conflict = ReceiverNames.hasConflict(prefs, name, protocol);
    if (!conflict && !alreadyRunning) {
      conflict = await ref
          .read(receiverNameProbeProvider)
          .hasConflict(
            name: name,
            protocol: protocol,
            localUuid: identity.uuid,
          );
      if (conflict) await ReceiverNames.recordConflict(prefs, name, protocol);
    }
    if (!ref.mounted) return name;
    final latest = protocol == 'AirPlay'
        ? state.airplayServerName
        : state.dlnaServerName;
    if (latest != name) return receiverNameForStart(protocol);
    if (!conflict) return name;
    await _reloadReceiverNames(identity);
    await _broadcastReceiverNames();
    return ReceiverNames.disambiguate(name, protocol, identity.shortCode);
  }

  Future<void> _broadcastReceiverNames() async {
    try {
      await _broadcastSettingChange(
        'update_receiver_names',
        _receiverNamesSnapshot(),
      );
    } catch (error) {
      debugPrint('[Receiver] name broadcast failed: $error');
    }
  }
}
