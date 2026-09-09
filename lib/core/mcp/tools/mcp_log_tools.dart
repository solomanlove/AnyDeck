import '../../adb/adb_service.dart';
import '../models/mcp_tool_definition.dart';

/// 设备日志检索与崩溃排查相关的 MCP Tools
class McpLogTools {
  final AdbService adbService;

  McpLogTools({required this.adbService});

  /// 获取所有日志工具
  List<McpToolDefinition> getTools() {
    return [
      _buildQueryLogcatTool(),
      _buildQueryAppCrashesTool(),
      _buildClearLogcatTool(),
    ];
  }

  /// 1. 查询指定设备当前的 Logcat 日志片段
  McpToolDefinition _buildQueryLogcatTool() {
    return McpToolDefinition(
      name: 'query_logcat',
      category: 'log',
      description: '检索设备当前的 Logcat 日志输出，支持按日志级别(V/D/I/W/E/F)、Tag 标签过滤及最大行数限制',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId'],
        'properties': {
          'deviceId': {'type': 'string', 'description': '目标设备序列号'},
          'tag': {'type': 'string', 'description': '日志 Tag 标签 (如 AndroidRuntime)'},
          'level': {
            'type': 'string',
            'enum': ['V', 'D', 'I', 'W', 'E', 'F'],
            'description': '最低日志级别 (V=Verbose, D=Debug, I=Info, W=Warn, E=Error, F=Fatal)',
            'default': 'I',
          },
          'limitLines': {
            'type': 'integer',
            'description': '最大读取行数 (默认 100 行，上限 500 行)',
            'default': 100,
          },
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String;
        final tag = args['tag'] as String?;
        final level = args['level'] as String? ?? 'I';
        final limit = ((args['limitLines'] as num?)?.toInt() ?? 100).clamp(1, 500);

        final logcatArgs = <String>['logcat', '-d', '-t', '$limit', '-v', 'time'];
        if (tag != null && tag.isNotEmpty) {
          logcatArgs.add('$tag:$level');
          logcatArgs.add('*:S');
        } else {
          logcatArgs.add('*:$level');
        }

        final result = await adbService.shellArgs(deviceId, logcatArgs);
        if (!result.isSuccess) {
          throw Exception('读取 Logcat 失败: ${result.stderr}');
        }

        final rawLines = result.stdout.split('\n');
        final cleanLines = rawLines
            .map((l) => l.trimRight())
            .where((l) => l.isNotEmpty)
            .toList();

        return {
          'deviceId': deviceId,
          'level': level,
          'tag': tag ?? 'all',
          'lineCount': cleanLines.length,
          'logs': cleanLines,
          'summary': '成功检索到 ${cleanLines.length} 条 Logcat 记录',
        };
      },
    );
  }

  /// 2. 检索设备最近发生的致命崩溃与 ANR
  McpToolDefinition _buildQueryAppCrashesTool() {
    return McpToolDefinition(
      name: 'query_app_crashes',
      category: 'log',
      description: '检索设备上最近发生的 Android 崩溃 (Crash)、未捕获异常及 ANR 错误堆栈',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId'],
        'properties': {
          'deviceId': {'type': 'string', 'description': '目标设备序列号'},
          'packageName': {'type': 'string', 'description': '指定过滤的应用包名(可选)'},
          'limit': {'type': 'integer', 'description': '检索最大行数', 'default': 200},
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String;
        final packageName = args['packageName'] as String?;
        final limit = ((args['limit'] as num?)?.toInt() ?? 200).clamp(10, 500);

        // 优先从 logcat 中抓取 AndroidRuntime 致命错误
        final result = await adbService.shellArgs(deviceId, [
          'logcat',
          '-d',
          '-t',
          '$limit',
          'AndroidRuntime:E',
          '*:S',
        ]);

        return {
          'deviceId': deviceId,
          'packageName': packageName ?? 'all',
          'crashes': result.stdout,
          'summary': result.stdout.trim().isEmpty
              ? '最近未检测到 AndroidRuntime 致命崩溃'
              : '检测到崩溃堆栈信息，请参考详细内容',
        };
      },
    );
  }

  /// 3. 清空当前 Logcat 缓冲区
  McpToolDefinition _buildClearLogcatTool() {
    return McpToolDefinition(
      name: 'clear_logcat',
      category: 'log',
      description: '清空指定设备的 Logcat 环形缓冲区',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId'],
        'properties': {
          'deviceId': {'type': 'string', 'description': '目标设备序列号'},
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String;
        final result = await adbService.shellArgs(deviceId, ['logcat', '-c']);
        if (!result.isSuccess) {
          throw Exception('清空 Logcat 失败: ${result.stderr}');
        }

        return {
          'deviceId': deviceId,
          'success': true,
          'summary': '设备 Logcat 缓冲区已成功清空',
        };
      },
    );
  }
}
