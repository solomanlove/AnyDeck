import '../../adb/adb_device.dart';
import 'device_registry_storage.dart';
import 'registered_device_model.dart';

/// 设备注册表多通道合并与候选代表选举服务。
///
/// 负责将实时在线设备流（ADB/HDC/iOS）与本地历史离线记录合并；
/// 处理同机多通道（如同时连接 USB 与 Wi-Fi）按序列号归一，并按“在线优先、USB 优先”选举最佳代表展示。
class DeviceRegistryMerger {
  /// 执行设备列表合并与候选代表选举。
  static List<RegisteredDevice> mergeDevices({
    required List<AdbDevice> activeDevices,
    required List<String> historyIds,
    required Map<String, String> aliases,
    required Map<String, String> models,
    required Map<String, String> products,
    required Map<String, String> ipAddresses,
    required Map<String, String> androidVersions,
    required Map<String, int> sdkVersions,
    required Map<String, String> remarks,
    required Map<String, List<String>> tags,
    required Set<String> checkedIds,
    required Map<String, String> serialMap,
  }) {
    final activeMap = <String, AdbDevice>{};
    for (final device in activeDevices) {
      final existing = activeMap[device.id];
      // 同一地址被 ADB 与 HDC 同时发现时，在线优先；状态相同时保留 ADB 路由。
      if (existing == null ||
          (device.isOnline && !existing.isOnline) ||
          (device.isOnline == existing.isOnline &&
              existing.isHarmony &&
              !device.isHarmony)) {
        activeMap[device.id] = device;
      }
    }

    final allCandidates = <RegisteredDevice>[];
    for (final id in historyIds) {
      final active = activeMap[id];
      final customName = aliases[id];
      final isChecked = checkedIds.contains(id);
      final serial = serialMap[id] ?? id;
      final cachedModel = models[id];
      final cachedProduct = products[id];
      final ipAddress = ipAddresses[serial] ?? ipAddresses[id];
      final androidVersion = androidVersions[serial] ?? androidVersions[id];
      final sdkVersion = sdkVersions[serial] ?? sdkVersions[id];

      final remark = remarks[id];
      final deviceTags = tags[id] ?? [];

      if (active != null) {
        // 对鸿蒙设备，若 active 或 models 缓存中已有真实设备名（非通用占位符），优先使用真实型号
        String? effectiveModel;
        if (active.isHarmony) {
          if (active.model != null && !DeviceRegistryStorage.isGenericHarmonyModel(active.model)) {
            effectiveModel = active.model;
          } else if (cachedModel != null && !DeviceRegistryStorage.isGenericHarmonyModel(cachedModel)) {
            effectiveModel = cachedModel;
          } else {
            effectiveModel = 'HarmonyOS Device';
          }
        } else {
          effectiveModel = active.model ?? cachedModel;
        }
        allCandidates.add(
          RegisteredDevice(
            id: id,
            customName: customName,
            status: active.status,
            model: effectiveModel,
            product: active.product ?? cachedProduct,
            transportId: active.transportId,
            isOnline: active.isOnline,
            isChecked: isChecked,
            connections: [id],
            serial: serial,
            ipAddress: ipAddress,
            androidVersion: androidVersion,
            sdkVersion: sdkVersion,
            isIos: active.isIos,
            isHarmony: active.isHarmony,
            remark: remark,
            tags: deviceTags,
          ),
        );
      } else {
        String? effectiveOfflineModel = cachedModel;
        if (DeviceRegistryStorage.isGenericHarmonyModel(effectiveOfflineModel)) {
          final sModel = models[serial];
          if (sModel != null && !DeviceRegistryStorage.isGenericHarmonyModel(sModel)) {
            effectiveOfflineModel = sModel;
          }
        }
        allCandidates.add(
          RegisteredDevice(
            id: id,
            customName: customName,
            status: 'offline',
            model: effectiveOfflineModel,
            product: cachedProduct,
            isOnline: false,
            isChecked: isChecked,
            connections: [id],
            serial: serial,
            ipAddress: ipAddress,
            androidVersion: androidVersion,
            sdkVersion: sdkVersion,
            remark: remark,
            tags: deviceTags,
            isIos:
                cachedModel != null &&
                (cachedModel.contains('iPhone') ||
                    cachedModel.contains('iPad') ||
                    cachedModel.contains('Apple') ||
                    cachedModel.contains('iOS') ||
                    id.length == 40 ||
                    (id.length == 25 && id.indexOf('-') == 8)),
            isHarmony:
                cachedProduct == 'HarmonyOS NEXT' ||
                (cachedModel != null &&
                    (cachedModel.contains('HarmonyOS') ||
                        cachedModel.contains('HOS'))),
          ),
        );
      }
    }

    // 按序列号分组
    final groups = <String, List<RegisteredDevice>>{};
    for (final candidate in allCandidates) {
      final serial = serialMap[candidate.id] ?? candidate.id;
      groups.putIfAbsent(serial, () => []).add(candidate);
    }

    // 每个序列号只选出一个最佳候选做代表来进行去重
    final merged = <RegisteredDevice>[];
    groups.forEach((serial, candidates) {
      if (candidates.length == 1) {
        final c = candidates.first;
        final effectiveRemark = (c.remark != null && c.remark!.isNotEmpty)
            ? c.remark
            : (remarks[serial] ?? remarks[c.id]);
        final effectiveTags = c.tags.isNotEmpty
            ? c.tags
            : (tags[serial] ?? tags[c.id] ?? []);
        merged.add(
          c.copyWith(
            remark: effectiveRemark,
            tags: effectiveTags,
          ),
        );
      } else {
        // 排序规则：在线优先，USB 优先，其次传统 TCP/IP 5555 端口优先
        candidates.sort((a, b) {
          if (a.isOnline && !b.isOnline) return -1;
          if (!a.isOnline && b.isOnline) return 1;

          final aIsUsb = a.hasUsbConnection;
          final bIsUsb = b.hasUsbConnection;
          if (aIsUsb && !bIsUsb) return -1;
          if (!aIsUsb && bIsUsb) return 1;

          final aIsTcp = a.hasTcpConnection;
          final bIsTcp = b.hasTcpConnection;
          if (aIsTcp && !bIsTcp) return -1;
          if (!aIsTcp && bIsTcp) return 1;

          return a.id.compareTo(b.id);
        });

        final best = candidates.first;
        final anyChecked = candidates.any((c) => c.isChecked);

        String? mergedCustomName;
        for (final c in candidates) {
          if (c.customName != null && c.customName!.isNotEmpty) {
            mergedCustomName = c.customName;
            break;
          }
        }

        String? mergedModel = best.model;
        if (mergedModel == null || mergedModel.isEmpty || DeviceRegistryStorage.isGenericHarmonyModel(mergedModel)) {
          for (final c in candidates) {
            if (c.model != null && c.model!.isNotEmpty && !DeviceRegistryStorage.isGenericHarmonyModel(c.model)) {
              mergedModel = c.model;
              break;
            }
          }
        }

        String? mergedProduct = best.product;
        if (mergedProduct == null || mergedProduct.isEmpty) {
          for (final c in candidates) {
            if (c.product != null && c.product!.isNotEmpty) {
              mergedProduct = c.product;
              break;
            }
          }
        }

        String? mergedIp = best.ipAddress;
        if (mergedIp == null || mergedIp.isEmpty || mergedIp == '-') {
          for (final c in candidates) {
            if (c.ipAddress != null &&
                c.ipAddress!.isNotEmpty &&
                c.ipAddress != '-') {
              mergedIp = c.ipAddress;
              break;
            }
          }
        }

        String? mergedAndroidVersion = best.androidVersion;
        if (mergedAndroidVersion == null || mergedAndroidVersion.isEmpty) {
          for (final c in candidates) {
            if (c.androidVersion != null && c.androidVersion!.isNotEmpty) {
              mergedAndroidVersion = c.androidVersion;
              break;
            }
          }
        }

        int? mergedSdkVersion = best.sdkVersion;
        if (mergedSdkVersion == null) {
          for (final c in candidates) {
            if (c.sdkVersion != null) {
              mergedSdkVersion = c.sdkVersion;
              break;
            }
          }
        }

        String? mergedRemark;
        for (final c in candidates) {
          if (c.remark != null && c.remark!.isNotEmpty) {
            mergedRemark = c.remark;
            break;
          }
        }
        mergedRemark ??= (remarks[serial] ?? remarks[best.id]);

        List<String> mergedTags = [];
        for (final c in candidates) {
          if (c.tags.isNotEmpty) {
            mergedTags = c.tags;
            break;
          }
        }
        if (mergedTags.isEmpty) {
          mergedTags = tags[serial] ?? tags[best.id] ?? [];
        }

        final connectionIds = best.isOnline
            ? candidates.where((c) => c.isOnline).map((c) => c.id).toList()
            : candidates.map((c) => c.id).toList();

        merged.add(
          best.copyWith(
            id: best.preferredCommandId,
            isChecked: anyChecked,
            customName: mergedCustomName,
            model: mergedModel,
            product: mergedProduct,
            connections: connectionIds,
            serial: serial,
            ipAddress: mergedIp,
            androidVersion: mergedAndroidVersion,
            sdkVersion: mergedSdkVersion,
            remark: mergedRemark,
            tags: mergedTags,
          ),
        );
      }
    });

    return merged;
  }
}
