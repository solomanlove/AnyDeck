import 'dart:io';

import '../../ios/ios_command_service.dart';
import '../models/mcp_tool_definition.dart';

/// 仅开放 go-ios 已接入的 App 与 AFC 文件能力。
class McpIosTools {
  McpIosTools({required this.commands, required this.isIosDevice});

  final IosCommandService commands;
  final Future<bool> Function(String deviceId) isIosDevice;

  Future<String> _udid(Map<String, dynamic> args) async {
    final value = args['deviceId'];
    if (value is! String || value.isEmpty || !await isIosDevice(value)) {
      throw ArgumentError('请提供在线 iOS 设备的 UDID');
    }
    return value;
  }

  List<McpToolDefinition> getTools() => [
    McpToolDefinition(
      name: 'ios_list_apps',
      category: 'app',
      description: '列出 iOS 已安装应用及 Bundle ID',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId'],
        'properties': {
          'deviceId': {'type': 'string'},
        },
      },
      handler: (args) async {
        final udid = await _udid(args);
        final apps = await commands.listApps(udid);
        return {
          'deviceId': udid,
          'count': apps.length,
          'apps': apps
              .map(
                (app) => {
                  'bundleId': app.bundleId,
                  'name': app.name,
                  'version': app.version,
                  'system': app.system,
                },
              )
              .toList(),
        };
      },
    ),
    McpToolDefinition(
      name: 'ios_install_ipa',
      category: 'app',
      description: '安装已正确签名的本地 IPA',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId', 'ipaPath'],
        'properties': {
          'deviceId': {'type': 'string'},
          'ipaPath': {'type': 'string'},
        },
      },
      handler: (args) async {
        final udid = await _udid(args);
        final path = args['ipaPath'] as String;
        if (!path.toLowerCase().endsWith('.ipa') ||
            !await File(path).exists()) {
          throw ArgumentError('IPA 文件不存在或扩展名无效');
        }
        final result = await commands.installApp(udid, path);
        if (!result.isSuccess) throw StateError(result.message);
        return {'deviceId': udid, 'success': true};
      },
    ),
    McpToolDefinition(
      name: 'ios_uninstall_app',
      category: 'app',
      isDangerous: true,
      description: '卸载 iOS 用户应用，调用前需确认 Bundle ID',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId', 'bundleId'],
        'properties': {
          'deviceId': {'type': 'string'},
          'bundleId': {'type': 'string'},
        },
      },
      handler: (args) async {
        final udid = await _udid(args);
        final bundleId = args['bundleId'] as String;
        final apps = await commands.listApps(udid);
        if (!apps.any((app) => app.bundleId == bundleId && !app.system)) {
          throw ArgumentError('目标不是可卸载的 iOS 用户应用');
        }
        final result = await commands.uninstallApp(udid, bundleId);
        if (!result.isSuccess) throw StateError(result.message);
        return {'deviceId': udid, 'bundleId': bundleId, 'success': true};
      },
    ),
    McpToolDefinition(
      name: 'ios_list_files',
      category: 'file',
      description: '列出允许 AFC 访问的 iOS App container 文件',
      inputSchema: _fileSchema(['deviceId', 'bundleId', 'remotePath']),
      handler: (args) async {
        final udid = await _udid(args);
        final result = await commands.listFiles(
          udid,
          bundleId: args['bundleId'] as String,
          remotePath: args['remotePath'] as String,
        );
        if (!result.isSuccess) throw StateError(result.message);
        return {'deviceId': udid, 'listing': result.stdout};
      },
    ),
    McpToolDefinition(
      name: 'ios_file_push',
      category: 'file',
      description: '上传本地文件到允许 AFC 访问的 App container',
      inputSchema: _fileSchema([
        'deviceId',
        'bundleId',
        'remotePath',
        'localPath',
      ]),
      handler: (args) async {
        final udid = await _udid(args);
        final path = args['localPath'] as String;
        if (!await File(path).exists()) throw ArgumentError('本地文件不存在');
        final result = await commands.pushFile(
          udid,
          bundleId: args['bundleId'] as String,
          localPath: path,
          remotePath: args['remotePath'] as String,
        );
        if (!result.isSuccess) throw StateError(result.message);
        return {'deviceId': udid, 'success': true};
      },
    ),
    McpToolDefinition(
      name: 'ios_file_pull',
      category: 'file',
      description: '从允许 AFC 访问的 App container 下载文件',
      inputSchema: _fileSchema([
        'deviceId',
        'bundleId',
        'remotePath',
        'localPath',
      ]),
      handler: (args) async {
        final udid = await _udid(args);
        final path = args['localPath'] as String;
        if (!File(path).isAbsolute) throw ArgumentError('本地保存路径必须是绝对路径');
        final result = await commands.pullFile(
          udid,
          bundleId: args['bundleId'] as String,
          remotePath: args['remotePath'] as String,
          localPath: path,
        );
        if (!result.isSuccess) throw StateError(result.message);
        return {'deviceId': udid, 'success': true};
      },
    ),
  ];

  static Map<String, dynamic> _fileSchema(List<String> required) => {
    'type': 'object',
    'required': required,
    'properties': {
      'deviceId': {'type': 'string'},
      'bundleId': {'type': 'string'},
      'remotePath': {'type': 'string'},
      'localPath': {'type': 'string'},
    },
  };
}
