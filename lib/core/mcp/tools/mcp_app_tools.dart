import '../../apps/app_management_service.dart';
import '../models/mcp_tool_definition.dart';

/// 应用生命周期与软件包管理相关的 MCP Tools
class McpAppTools {
  final AppManagementService appService;

  McpAppTools({required this.appService});

  /// 获取所有应用管理工具
  List<McpToolDefinition> getTools() {
    return [
      _buildListInstalledAppsTool(),
      _buildInstallAppTool(),
      _buildUninstallAppTool(),
      _buildLaunchAppTool(),
      _buildStopAppTool(),
      _buildClearAppDataTool(),
    ];
  }

  /// 1. 获取已安装应用包名列表
  McpToolDefinition _buildListInstalledAppsTool() {
    return McpToolDefinition(
      name: 'list_installed_apps',
      category: 'app',
      description: '列出目标设备上安装的应用程序包名列表（支持按系统应用/第三方应用过滤）',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId'],
        'properties': {
          'deviceId': {'type': 'string', 'description': '目标设备序列号'},
          'filter': {
            'type': 'string',
            'enum': ['all', 'third_party', 'system'],
            'description': '过滤类型: all(全部), third_party(第三方应用), system(系统应用)',
            'default': 'all',
          },
          'forceRefresh': {
            'type': 'boolean',
            'description': '是否强制刷新设备上的应用缓存',
            'default': false,
          },
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String;
        final filter = args['filter'] as String? ?? 'all';
        final forceRefresh = args['forceRefresh'] as bool? ?? false;

        final packages = await appService.listPackages(deviceId, forceRefresh: forceRefresh);
        final filtered = packages.where((p) {
          if (filter == 'third_party') return !p.system;
          if (filter == 'system') return p.system;
          return true;
        }).map((p) {
          return {
            'packageName': p.name,
            'appName': p.label ?? p.name,
            'versionName': p.versionName,
            'versionCode': p.versionCode,
            'isSystem': p.system,
            'isEnabled': p.enabled,
          };
        }).toList();

        return {
          'deviceId': deviceId,
          'filter': filter,
          'total': filtered.length,
          'apps': filtered,
          'summary': '找到 ${filtered.length} 个符合条件的应用',
        };
      },
    );
  }

  /// 2. 安装本地 APK 软件包
  McpToolDefinition _buildInstallAppTool() {
    return McpToolDefinition(
      name: 'install_app',
      category: 'app',
      description: '向指定设备推送并安装本地 APK 软件包',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId', 'apkPath'],
        'properties': {
          'deviceId': {'type': 'string', 'description': '目标设备序列号'},
          'apkPath': {'type': 'string', 'description': '宿主机上的本地 APK 绝对路径'},
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String;
        final apkPath = args['apkPath'] as String;

        final result = await appService.installApk(deviceId, apkPath);

        if (!result.isSuccess) {
          throw Exception('安装失败: ${result.stderr.isNotEmpty ? result.stderr : result.stdout}');
        }

        return {
          'deviceId': deviceId,
          'apkPath': apkPath,
          'success': true,
          'summary': 'APK 安装成功',
        };
      },
    );
  }

  /// 3. 卸载应用 (敏感高危操作)
  McpToolDefinition _buildUninstallAppTool() {
    return McpToolDefinition(
      name: 'uninstall_app',
      category: 'app',
      isDangerous: true,
      description: '卸载指定设备上的应用程序',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId', 'packageName'],
        'properties': {
          'deviceId': {'type': 'string', 'description': '目标设备序列号'},
          'packageName': {'type': 'string', 'description': '目标应用包名'},
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String;
        final packageName = args['packageName'] as String;

        final result = await appService.uninstall(deviceId, packageName);

        if (!result.isSuccess) {
          throw Exception('卸载失败: ${result.stderr.isNotEmpty ? result.stderr : result.stdout}');
        }

        return {
          'deviceId': deviceId,
          'packageName': packageName,
          'success': true,
          'summary': '应用 $packageName 卸载成功',
        };
      },
    );
  }

  /// 4. 启动应用
  McpToolDefinition _buildLaunchAppTool() {
    return McpToolDefinition(
      name: 'launch_app',
      category: 'app',
      description: '启动设备上的指定应用',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId', 'packageName'],
        'properties': {
          'deviceId': {'type': 'string', 'description': '目标设备序列号'},
          'packageName': {'type': 'string', 'description': '应用包名'},
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String;
        final packageName = args['packageName'] as String;

        final result = await appService.launch(deviceId, packageName);

        if (!result.isSuccess) {
          throw Exception('启动应用失败: ${result.stderr}');
        }

        return {
          'deviceId': deviceId,
          'packageName': packageName,
          'success': true,
          'summary': '应用 $packageName 已启动',
        };
      },
    );
  }

  /// 5. 强制停止应用
  McpToolDefinition _buildStopAppTool() {
    return McpToolDefinition(
      name: 'stop_app',
      category: 'app',
      description: '强行停止(Force Stop)正在运行的应用进程',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId', 'packageName'],
        'properties': {
          'deviceId': {'type': 'string', 'description': '目标设备序列号'},
          'packageName': {'type': 'string', 'description': '应用包名'},
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String;
        final packageName = args['packageName'] as String;

        final result = await appService.forceStop(deviceId, packageName);
        if (!result.isSuccess) {
          throw Exception('停止应用失败: ${result.stderr}');
        }

        return {
          'deviceId': deviceId,
          'packageName': packageName,
          'success': true,
          'summary': '应用 $packageName 进程已被强制终止',
        };
      },
    );
  }

  /// 6. 清除应用数据与缓存 (敏感高危操作)
  McpToolDefinition _buildClearAppDataTool() {
    return McpToolDefinition(
      name: 'clear_app_data',
      category: 'app',
      isDangerous: true,
      description: '清除应用程序的全部用户数据与缓存(pm clear)',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId', 'packageName'],
        'properties': {
          'deviceId': {'type': 'string', 'description': '目标设备序列号'},
          'packageName': {'type': 'string', 'description': '应用包名'},
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String;
        final packageName = args['packageName'] as String;

        final result = await appService.clearData(deviceId, packageName);
        if (!result.isSuccess) {
          throw Exception('清除应用数据失败: ${result.stderr}');
        }

        return {
          'deviceId': deviceId,
          'packageName': packageName,
          'success': true,
          'summary': '应用 $packageName 数据已成功清除',
        };
      },
    );
  }
}
