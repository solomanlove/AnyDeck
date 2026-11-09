import 'dart:async';
import '../models/mcp_tool_definition.dart';
import '../security/mcp_security_guard.dart';

/// MCP 工具注册与调用分发中心
class McpToolRegistry {
  final Map<String, McpToolDefinition> _tools = {};
  final Map<String, Future<void>> _deviceQueues = {};
  Future<bool> Function(String deviceId)? isIosDevice;
  Future<String?> Function(String deviceId)? resolvePlatform;

  /// 注册单个工具
  void register(McpToolDefinition tool) {
    _tools[tool.name] = tool;
  }

  /// 批量注册工具集合
  void registerAll(List<McpToolDefinition> tools) {
    for (final tool in tools) {
      register(tool);
    }
  }

  /// 获取所有已注册工具列表
  List<McpToolDefinition> getAllTools() => _tools.values.toList();

  /// 根据名称查找工具
  McpToolDefinition? findTool(String name) => _tools[name];

  /// 生成 MCP 规范的 tools 描述列表
  List<Map<String, dynamic>> toMcpToolsSchema({
    Set<String> disabledTools = const {},
    String platform = 'all',
    Set<String> enabledCategories = const {},
  }) {
    final tools = _tools.values
        .where((t) => !disabledTools.contains(t.name) &&
            (platform == 'all' || t.platforms.contains(platform)) &&
            (enabledCategories.isEmpty || enabledCategories.contains(t.category)))
        .map((t) => t.toMcpSchema())
        .toList();
    tools.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return tools;
  }

  /// 执行指定工具调用
  Future<Map<String, dynamic>> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
    bool enableDangerousGuard = true,
    Set<String> disabledTools = const {},
    String platform = 'all',
    Set<String> enabledCategories = const {},
  }) async {
    final tool = _tools[name];
    if (tool == null) {
      throw ArgumentError('未找到工具: $name');
    }

    if (platform != 'all' && !tool.platforms.contains(platform)) {
      throw UnsupportedError('工具 $name 不属于 $platform 入口');
    }
    if (enabledCategories.isNotEmpty && !enabledCategories.contains(tool.category)) {
      throw StateError('工具分类 ${tool.category} 已禁用');
    }


    // 校验安全规则与禁用状态
    final blockReason = McpSecurityGuard.checkToolExecutionAllowed(
      toolName: name,
      isDangerous: tool.isDangerous,
      enableDangerousGuard: enableDangerousGuard,
      disabledTools: disabledTools,
    );

    if (blockReason != null) {
      throw StateError(blockReason);
    }

    final deviceId = arguments['deviceId'];
    if (deviceId is String && resolvePlatform != null) {
      final actual = await resolvePlatform!(deviceId);
      if (actual == null || !tool.platforms.contains(actual) ||
          (platform != 'all' && actual != platform)) {
        throw UnsupportedError('设备不存在、离线或与工具平台不匹配，请先调用 list_devices');
      }
    } else if (platform != 'all' && deviceId is String) {
      throw StateError('平台设备解析器未配置');
    }
    if (deviceId is String && deviceId.isNotEmpty &&
        await isIosDevice?.call(deviceId) == true &&
        !tool.platforms.contains('ios')) {
      throw UnsupportedError('工具 $name 不支持 iOS 设备');
    }

    _validateArguments(tool.inputSchema, arguments);
    if (deviceId is! String) return await tool.handler(arguments);
    // 同一设备的布局抓取、触控和应用命令按到达顺序执行，避免跨客户端互相覆盖。
    final previous = _deviceQueues[deviceId];
    final done = Completer<void>();
    _deviceQueues[deviceId] = done.future;
    try {
      await previous;
      return await tool.handler(arguments);
    } finally {
      done.complete();
      if (identical(_deviceQueues[deviceId], done.future)) _deviceQueues.remove(deviceId);
    }
  }

  /// 在进入 CLI 前校验必填项、类型、枚举和数值边界。
  void _validateArguments(Map<String, dynamic> schema, Map<String, dynamic> args) {
    for (final key in (schema['required'] as List? ?? [])) {
      if (!args.containsKey(key)) throw ArgumentError('缺少参数 $key');
    }
    final properties = schema['properties'] as Map? ?? {};
    for (final entry in args.entries) {
      final rule = properties[entry.key];
      if (rule is! Map) throw ArgumentError('未知参数 ${entry.key}');
      final v = entry.value;
      final valid = switch (rule['type']) {
        'string' => v is String && v.isNotEmpty && !v.contains('\u0000'),
        'boolean' => v is bool,
        'integer' => v is int,
        'number' => v is num && v.isFinite,
        _ => false,
      };
      if (!valid) throw ArgumentError('参数 ${entry.key} 类型或值无效');
      if (v is String && rule['pattern'] is String &&
          !RegExp(rule['pattern'] as String).hasMatch(v)) {
        throw ArgumentError('参数 ${entry.key} 格式无效');
      }
      if (rule['enum'] is List && !(rule['enum'] as List).contains(v)) {
        throw ArgumentError('参数 ${entry.key} 不在允许范围内');
      }
      if (v is num && ((rule['minimum'] is num && v < rule['minimum']) ||
          (rule['maximum'] is num && v > rule['maximum']))) {
        throw ArgumentError('参数 ${entry.key} 超出范围');
      }
    }
  }
}
