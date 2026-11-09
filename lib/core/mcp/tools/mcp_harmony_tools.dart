import 'dart:io';
import '../../harmony/hdc_service.dart';
import '../models/mcp_tool_definition.dart';

/// HarmonyOS 专属能力，参数经过校验后才交给 HDC。
class McpHarmonyTools {
  McpHarmonyTools(this.hdc);
  final HdcService hdc;

  /// 概览只返回实际读取的输出，不把缺失信息填充为 Android 字段。
  Future<Map<String, dynamic>> detail(String id) async {
    final result = await hdc.shell(
      id,
      'param get const.product.model; param get const.ohos.fullname; uname -r',
    );
    if (!result.isSuccess) throw StateError(result.message);
    return {
      'deviceId': id,
      'platform': 'harmony',
      'dataSource': 'live',
      'collectedAt': DateTime.now().toUtc().toIso8601String(),
      'rawInfo': result.stdout,
      'partial': true,
    };
  }

  List<McpToolDefinition> getTools() => [
    McpToolDefinition(
      name: 'harmony_install_app',
      category: 'app',
      platforms: const {'harmony'},
      description: '安装本机已签名 HAP/HSP 到在线 HarmonyOS 设备；可能覆盖同包应用，需要设备允许调试安装',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId', 'hapPath'],
        'properties': {
          'deviceId': {'type': 'string'},
          'hapPath': {
            'type': 'string',
            'description': 'AnyDeck 宿主机上的 HAP/HSP 绝对路径',
          },
        },
      },
      handler: (args) async {
        final path = args['hapPath'] as String;
        if (!File(path).isAbsolute ||
            !RegExp(r'\.(hap|hsp)$', caseSensitive: false).hasMatch(path) ||
            !await File(path).exists()) {
          throw ArgumentError('请提供存在的 HAP/HSP 绝对路径');
        }
        final result = await hdc.installApp(args['deviceId'] as String, path);
        if (!result.isSuccess) throw StateError(result.message);
        return {'success': true, 'deviceId': args['deviceId']};
      },
    ),
    McpToolDefinition(
      name: 'query_hilog',
      category: 'log',
      platforms: const {'harmony'},
      readOnly: true,
      description: '读取 HarmonyOS 当前 hilog 缓冲区的有限快照，按关键词过滤；不是完整崩溃或 ANR 报告',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId'],
        'properties': {
          'deviceId': {'type': 'string'},
          'keyword': {'type': 'string'},
          'limitLines': {
            'type': 'integer',
            'minimum': 1,
            'maximum': 500,
            'default': 100,
          },
        },
      },
      handler: (args) async {
        final limit = args['limitLines'] as int? ?? 100;
        final result = await hdc.shell(
          args['deviceId'] as String,
          'hilog -x -t 500',
        );
        if (!result.isSuccess) throw StateError(result.message);
        final lines = result.stdout
            .split('\n')
            .where(
              (l) =>
                  l.isNotEmpty && l.contains(args['keyword'] as String? ?? ''),
            )
            .toList();
        return {
          'deviceId': args['deviceId'],
          'logs': lines.reversed.take(limit).toList().reversed.toList(),
          'truncated': lines.length > limit,
          'source': 'hilog',
        };
      },
    ),
  ];
}
