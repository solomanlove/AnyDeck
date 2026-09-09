import 'dart:io';

import '../../adb/adb_service.dart';
import '../../files/file_manager_service.dart';
import '../models/mcp_tool_definition.dart';
import '../security/mcp_security_guard.dart';

/// 文件传输与受控 Shell 相关的 MCP Tools
class McpFileTools {
  final AdbService adbService;
  final FileManagerService? fileManagerService;

  McpFileTools({
    required this.adbService,
    this.fileManagerService,
  });

  /// 获取所有文件与 Shell 工具
  List<McpToolDefinition> getTools() {
    return [
      _buildListFilesTool(),
      _buildPushFileTool(),
      _buildPullFileTool(),
      _buildExecuteShellTool(),
    ];
  }

  /// 1. 列出设备指定目录下的文件列表
  McpToolDefinition _buildListFilesTool() {
    return McpToolDefinition(
      name: 'list_files',
      category: 'file',
      description: '列出目标设备指定目录下的所有文件与子文件夹元数据（权限、大小、修改时间）',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId'],
        'properties': {
          'deviceId': {'type': 'string', 'description': '目标设备序列号'},
          'remotePath': {
            'type': 'string',
            'description': '目标目录绝对路径 (默认 /sdcard/)',
            'default': '/sdcard/',
          },
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String;
        final remotePath = args['remotePath'] as String? ?? '/sdcard/';

        final result = await adbService.shellArgs(deviceId, ['ls', '-la', remotePath]);
        if (!result.isSuccess) {
          throw Exception('列出目录失败: ${result.stderr}');
        }

        final rawLines = result.stdout.split('\n');
        final items = rawLines
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && !l.startsWith('total'))
            .toList();

        return {
          'deviceId': deviceId,
          'remotePath': remotePath,
          'itemCount': items.length,
          'items': items,
          'summary': '在 $remotePath 下找到 ${items.length} 个条目',
        };
      },
    );
  }

  /// 2. 上传本地文件到设备 (adb push)
  McpToolDefinition _buildPushFileTool() {
    return McpToolDefinition(
      name: 'file_push',
      category: 'file',
      description: '将本地宿主机上的文件推送到目标设备的指定目录',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId', 'localPath', 'remotePath'],
        'properties': {
          'deviceId': {'type': 'string', 'description': '目标设备序列号'},
          'localPath': {'type': 'string', 'description': '宿主机本地文件绝对路径'},
          'remotePath': {'type': 'string', 'description': '设备端目标绝对路径'},
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String;
        final localPath = args['localPath'] as String;
        final remotePath = args['remotePath'] as String;

        final file = File(localPath);
        if (!await file.exists()) {
          throw ArgumentError('本地文件不存在: $localPath');
        }

        final result = await adbService.run(['-s', deviceId, 'push', localPath, remotePath]);
        if (!result.isSuccess) {
          throw Exception('文件推送失败: ${result.stderr.isNotEmpty ? result.stderr : result.stdout}');
        }

        return {
          'deviceId': deviceId,
          'localPath': localPath,
          'remotePath': remotePath,
          'success': true,
          'summary': '文件已成功上传至设备: $remotePath',
        };
      },
    );
  }

  /// 3. 从设备下载文件至本地 (adb pull)
  McpToolDefinition _buildPullFileTool() {
    return McpToolDefinition(
      name: 'file_pull',
      category: 'file',
      description: '从目标设备拉取指定文件保存到本地宿主机路径',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId', 'remotePath', 'localPath'],
        'properties': {
          'deviceId': {'type': 'string', 'description': '目标设备序列号'},
          'remotePath': {'type': 'string', 'description': '设备端源文件绝对路径'},
          'localPath': {'type': 'string', 'description': '宿主机保存绝对路径'},
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String;
        final remotePath = args['remotePath'] as String;
        final localPath = args['localPath'] as String;

        final result = await adbService.run(['-s', deviceId, 'pull', remotePath, localPath]);
        if (!result.isSuccess) {
          throw Exception('文件拉取失败: ${result.stderr.isNotEmpty ? result.stderr : result.stdout}');
        }

        return {
          'deviceId': deviceId,
          'remotePath': remotePath,
          'localPath': localPath,
          'success': true,
          'summary': '文件已成功下载至: $localPath',
        };
      },
    );
  }

  /// 4. 执行受控的 Shell 命令 (敏感高危操作，受 McpSecurityGuard 防御保护)
  McpToolDefinition _buildExecuteShellTool() {
    return McpToolDefinition(
      name: 'execute_shell',
      category: 'shell',
      isDangerous: true,
      description: '在目标设备上执行自定义的 ADB Shell 命令行（内置安全沙箱拦截高危指令）',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId', 'command'],
        'properties': {
          'deviceId': {'type': 'string', 'description': '目标设备序列号'},
          'command': {'type': 'string', 'description': '要执行的 shell 命令字符串'},
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String;
        final command = args['command'] as String;

        // 安全拦截检测
        final blockReason = McpSecurityGuard.checkDangerousShellCommand(command);
        if (blockReason != null) {
          throw Exception(blockReason);
        }

        final result = await adbService.shell(deviceId, command);

        return {
          'deviceId': deviceId,
          'command': command,
          'exitCode': result.exitCode,
          'stdout': result.stdout,
          'stderr': result.stderr,
          'isSuccess': result.isSuccess,
        };
      },
    );
  }
}
