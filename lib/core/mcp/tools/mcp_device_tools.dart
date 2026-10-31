import '../../adb/adb_service.dart';
import '../../device_info/device_info_service.dart';
import '../../device_info/device_overview.dart';
import '../../ios/ios_command_service.dart';
import '../../ios/ios_device_service.dart';
import '../../ios/ios_overview_service.dart';
import '../models/mcp_tool_definition.dart';
import 'mcp_battery_snapshot.dart';

/// 设备与系统状态感知相关的 MCP Tools
class McpDeviceTools {
  final AdbService adbService;
  final DeviceInfoService deviceInfoService;
  final IosDeviceService? iosDeviceService;
  final IosCommandService? iosCommandService;
  final Future<bool> Function(String deviceId)? isIosDevice;

  McpDeviceTools({
    required this.adbService,
    required this.deviceInfoService,
    this.iosDeviceService,
    this.iosCommandService,
    this.isIosDevice,
  });

  /// 获取所有注册的设备工具
  List<McpToolDefinition> getTools() {
    return [
      _buildListDevicesTool(),
      _buildGetDeviceDetailTool(),
      _buildGetBatteryInfoTool(),
    ];
  }

  /// 1. 获取已连接设备列表
  McpToolDefinition _buildListDevicesTool() {
    return McpToolDefinition(
      name: 'list_devices',
      category: 'device',
      description: '获取当前连接到宿主机的 Android、iOS 等设备列表',
      inputSchema: {
        'type': 'object',
        'properties': {
          'forceRefresh': {
            'type': 'boolean',
            'description': '是否强制重新扫描设备列表',
            'default': false,
          },
        },
      },
      handler: (args) async {
        final devices = (await adbService.listDevices()).toList();
        // iOS 枚举失败不应使已连接的 Android 设备消失。
        try {
          devices.addAll(await iosDeviceService?.listDevices() ?? []);
        } catch (_) {}
        final deviceListJson = devices.map((d) {
          return {
            'id': d.id,
            'model': d.model,
            'status': d.status,
            'isOnline': d.isOnline,
            'isIos': d.isIos,
            'isHarmony': d.isHarmony,
            'displayName': d.displayName,
          };
        }).toList();

        return {
          'devices': deviceListJson,
          'count': deviceListJson.length,
          'summary': '已成功发现 ${deviceListJson.length} 台设备',
        };
      },
    );
  }

  /// 2. 获取指定设备的详细信息
  McpToolDefinition _buildGetDeviceDetailTool() {
    return McpToolDefinition(
      name: 'get_device_detail',
      category: 'device',
      description: '获取指定设备可读取的软硬件参数；iOS 部分字段不可用',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId'],
        'properties': {
          'deviceId': {
            'type': 'string',
            'description': '目标设备序列号或 TCP/IP IP:Port 标识',
          },
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String?;
        if (deviceId == null || deviceId.isEmpty) {
          throw ArgumentError('必须提供 deviceId');
        }

        final ios = await isIosDevice?.call(deviceId) == true;
        try {
          final overview = ios
              ? await IosOverviewService(
                  iosCommandService ?? IosCommandService(),
                ).load(deviceId, fallbackName: deviceId)
              : await deviceInfoService.loadOverview(
                  deviceId,
                  allowCachedFallback: false,
                );
          if (ios && overview.model == '-' && overview.storage == '-') {
            throw StateError('iOS device information is unavailable');
          }
          final now = DateTime.now().toUtc();
          if (ios) {
            await deviceInfoService.saveToCache(
              deviceId,
              overview,
              collectedAt: now,
            );
          }
          return {
            ..._detailFields(overview),
            'deviceId': deviceId,
            'isIos': ios,
            'connectionState': 'online',
            'dataSource': 'live',
            'collectedAt': now.toIso8601String(),
            'checkedAt': now.toIso8601String(),
            'stale': false,
            if (ios) 'partial': overview.iosDetails?.partial ?? true,
          };
        } catch (error) {
          // 失败后的状态重新查询；不能沿用读取前的 online，或隐去缓存来源。
          final state = ios ? 'unknown' : await _connectionState(deviceId);
          final cached = await deviceInfoService.loadCachedSnapshot(deviceId);
          return {
            if (cached != null) ..._detailFields(cached.overview),
            'deviceId': deviceId,
            'isIos': ios,
            'connectionState': state,
            'dataSource': cached == null ? 'unavailable' : 'cache',
            'collectedAt': cached?.collectedAt?.toIso8601String(),
            'checkedAt': DateTime.now().toUtc().toIso8601String(),
            'stale': true,
            'readError': error.toString(),
          };
        }
      },
    );
  }

  /// 3. 获取电池状态与温度
  McpToolDefinition _buildGetBatteryInfoTool() {
    return McpToolDefinition(
      name: 'get_battery_info',
      category: 'device',
      description: '查询设备的实时电量、充放电状态、电池健康度及温度',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId'],
        'properties': {
          'deviceId': {
            'type': 'string',
            'description': '目标设备序列号',
          },
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String?;
        if (deviceId == null || deviceId.isEmpty) {
          throw ArgumentError('必须提供 deviceId');
        }

        final result = await adbService.shellArgs(deviceId, ['dumpsys', 'battery']);
        if (!result.isSuccess) {
          throw Exception('获取电池信息失败: ${result.stderr}');
        }

        return {
          'deviceId': deviceId,
          'dataSource': 'live',
          'collectedAt': DateTime.now().toUtc().toIso8601String(),
          ...McpBatterySnapshot.parse(result.stdout),
        };
      },
    );
  }

  /// 保留旧字段供已有客户端使用，状态元数据由调用处统一附加。
  Map<String, dynamic> _detailFields(DeviceOverview overview) => {
    'osVersion': overview.androidVersion,
    'name': overview.name,
    'model': overview.model,
    'brand': overview.brand,
    'serial': overview.serial,
    'androidVersion': overview.androidVersion,
    'processor': overview.processor,
    'resolution': overview.resolution,
    'logicalDensity': overview.logicalDensity,
    'ipAddress': overview.ipAddress,
    'storage': overview.storage,
    'memory': overview.memory,
  };

  Future<String> _connectionState(String deviceId) async {
    try {
      final result = await adbService.run(['-s', deviceId, 'get-state']);
      if (result.isSuccess && result.stdout.trim() == 'device') return 'online';
      final message = '${result.stdout} ${result.stderr}'.toLowerCase();
      if (message.contains('unauthorized')) return 'unauthorized';
      if (message.contains('offline')) return 'offline';
      if (message.contains('not found') || message.contains('no devices')) {
        return 'disconnected';
      }
    } catch (_) {
      // 状态查询失败只能判为未知，不能伪造 online 或 offline。
    }
    return 'unknown';
  }
}
