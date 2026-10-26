import '../models/mcp_tool_definition.dart';
import '../security/mcp_security_guard.dart';

/// MCP 工具注册与调用分发中心
class McpToolRegistry {
  final Map<String, McpToolDefinition> _tools = {};
  Future<bool> Function(String deviceId)? isIosDevice;

  static const _iosTools = {
    'list_devices', 'get_device_detail', 'take_screenshot',
    'inspect_ui_layout', 'device_input_tap', 'device_input_swipe',
    'device_input_text', 'device_press_key', 'ios_list_apps',
    'ios_install_ipa', 'ios_uninstall_app', 'ios_list_files',
    'ios_file_push', 'ios_file_pull',
  };

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
  }) {
    return _tools.values
        .where((t) => !disabledTools.contains(t.name))
        .map((t) => t.toMcpSchema())
        .toList();
  }

  /// 执行指定工具调用
  Future<Map<String, dynamic>> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
    bool enableDangerousGuard = true,
    Set<String> disabledTools = const {},
  }) async {
    final tool = _tools[name];
    if (tool == null) {
      throw ArgumentError('未找到工具: $name');
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
    if (deviceId is String && deviceId.isNotEmpty &&
        await isIosDevice?.call(deviceId) == true &&
        !_iosTools.contains(name)) {
      throw UnsupportedError('工具 $name 不支持 iOS 设备');
    }

    return await tool.handler(arguments);
  }
}
