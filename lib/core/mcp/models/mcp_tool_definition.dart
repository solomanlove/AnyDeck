/// MCP (Model Context Protocol) 工具定义模型
class McpToolDefinition {
  /// 工具唯一名称
  final String name;

  /// 工具功能描述，供大语言模型理解工具用途
  final String description;

  /// 输入参数 JSON Schema (符合 JSON Schema Draft 7/2020-12 规范)
  final Map<String, dynamic> inputSchema;

  /// 工具处理回调函数
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> arguments) handler;

  /// 工具所属分类 (device, ui, app, log, file, shell)
  final String category;

  /// 是否为高危敏感工具 (如卸载、清除数据、执行自定义 Shell)
  final bool isDangerous;

  /// 支持的平台；用于发现过滤与执行时的二次校验。
  final Set<String> platforms;

  /// 只读提示仅供客户端展示，服务端权限仍独立校验。
  final bool readOnly;


  const McpToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
    this.category = 'general',
    this.isDangerous = false,
    this.platforms = const {'android'},
    this.readOnly = false,
  });

  /// 转换为 MCP 协议规范的标准 Tool 描述 JSON
  Map<String, dynamic> toMcpSchema() {
    return {
      'name': name,
      'description': 'Platforms: ${platforms.join(', ')}. $description',
      'inputSchema': {...inputSchema, 'additionalProperties': false},
      'outputSchema': {'type': 'object'},
      'annotations': {
        'readOnlyHint': readOnly,
        'destructiveHint': isDangerous,
        'openWorldHint': false,
      },
    };
  }

  @override
  String toString() => 'McpToolDefinition(name: $name, category: $category)';
}
