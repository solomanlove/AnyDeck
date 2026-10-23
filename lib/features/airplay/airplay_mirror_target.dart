import '../../core/airplay/airplay_server_state.dart';
import '../../core/ios/ios_device_identity.dart';
import '../../core/providers/modules/registered_device_model.dart';

/// AirPlay 无法提供 USB UDID；优先按上报机型/名称匹配设备列表，其次关联在线 iOS 设备。
RegisteredDevice? resolveAirPlayMirrorTarget(
  Iterable<RegisteredDevice> devices, {
  AirPlaySessionData? session,
  Set<String> claimedDeviceIds = const {},
}) {
  final availableIos = devices
      .where((device) => device.isIos && !claimedDeviceIds.contains(device.id))
      .toList();
  if (availableIos.isEmpty) return null;

  final normalizedModel = IosDeviceIdentity.modelName(
    session?.clientModel,
    fallback: session?.clientName,
  );
  final rawName = session?.clientName?.trim();

  // 1. 若有明确的机型或客户端名称，优先精确匹配在线 iOS 设备，其次匹配历史离线同款设备
  if ((normalizedModel != null &&
          normalizedModel.isNotEmpty &&
          normalizedModel != 'iPhone') ||
      (rawName != null && rawName.isNotEmpty && rawName != 'iPhone')) {
    bool matchesIdentity(RegisteredDevice d) {
      final devModel = IosDeviceIdentity.modelName(d.model);
      if (normalizedModel != null &&
          normalizedModel.isNotEmpty &&
          normalizedModel != 'iPhone') {
        if (devModel == normalizedModel || d.displayName == normalizedModel) {
          return true;
        }
      }
      if (rawName != null && rawName.isNotEmpty && rawName != 'iPhone') {
        if (d.displayName == rawName || d.customName == rawName) {
          return true;
        }
      }
      return false;
    }

    final onlineMatched = availableIos
        .where((d) => d.isOnline && matchesIdentity(d))
        .toList();
    if (onlineMatched.isNotEmpty) {
      return onlineMatched.where((d) => d.hasUsbConnection).firstOrNull ??
          onlineMatched.first;
    }

    final offlineMatched = availableIos.where(matchesIdentity).firstOrNull;
    if (offlineMatched != null) return offlineMatched;

    // 当上报了具体型号但列表中无同型号设备时，若列表已有多台不同型号 iOS 设备，不强行张冠李戴
    if (normalizedModel != null &&
        normalizedModel.isNotEmpty &&
        normalizedModel != 'iPhone') {
      return null;
    }
  }

  // 2. 回退策略：优先关联在线 USB iOS 设备，其次回退至在线 Wi-Fi iOS 设备
  final onlineIos = availableIos.where((device) => device.isOnline).toList();
  return onlineIos.where((device) => device.hasUsbConnection).firstOrNull ??
      onlineIos.firstOrNull;
}

/// 将当前所有活跃的 AirPlay 投屏会话合并到设备列表中。
///
/// - 若匹配到列表中已有的 iOS 设备（例如截图中的 `iPhone X`），直接复用该行并挂载其投屏状态；
/// - 若存在未通过 `go-ios` 配对或多台并发 AirPlay 设备，则自动生成对应的在线设备行展示在列表中。
({
  List<RegisteredDevice> devices,
  Map<String, AirPlaySessionData> sessionByDeviceId,
}) mergeAirPlayDevicesIntoList(
  List<RegisteredDevice> devices,
  AirPlaySessionData? rootSession,
) {
  final mirroringSessions = rootSession?.mirroringSessions ?? const [];
  if (mirroringSessions.isEmpty) {
    return (devices: devices, sessionByDeviceId: const {});
  }

  final mergedDevices = List<RegisteredDevice>.from(devices);
  final sessionByDeviceId = <String, AirPlaySessionData>{};
  final claimedIds = <String>{};

  for (final session in mirroringSessions) {
    final matched = resolveAirPlayMirrorTarget(
      mergedDevices,
      session: session,
      claimedDeviceIds: claimedIds,
    );

    if (matched != null) {
      claimedIds.add(matched.id);
      sessionByDeviceId[matched.id] = session;
      final index = mergedDevices.indexWhere((d) => d.id == matched.id);
      if (index >= 0 && !mergedDevices[index].isOnline) {
        mergedDevices[index] = mergedDevices[index].copyWith(
          isOnline: true,
          status: 'device',
        );
      }
    } else {
      final rawDeviceId = session.clientDeviceId?.trim();
      final syntheticId = (rawDeviceId != null && rawDeviceId.isNotEmpty)
          ? 'airplay-$rawDeviceId'
          : 'airplay-${session.id}';
      final modelName =
          IosDeviceIdentity.modelName(
            session.clientModel,
            fallback: session.clientName,
          ) ??
          'iPhone';
      final clientName = session.clientName?.trim();
      final customName =
          (clientName != null &&
              clientName.isNotEmpty &&
              clientName != 'iPhone' &&
              clientName != modelName)
          ? clientName
          : null;

      final syntheticDevice = RegisteredDevice(
        id: syntheticId,
        customName: customName,
        model: modelName,
        status: 'device',
        isOnline: true,
        isIos: true,
        androidVersion: 'iOS',
      );
      claimedIds.add(syntheticId);
      sessionByDeviceId[syntheticId] = session;
      mergedDevices.insert(0, syntheticDevice);
    }
  }

  return (devices: mergedDevices, sessionByDeviceId: sessionByDeviceId);
}
