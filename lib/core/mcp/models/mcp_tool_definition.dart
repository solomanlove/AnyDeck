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

  const McpToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
    this.category = 'general',
    this.isDangerous = false,
  });

  /// 转换为 MCP 协议规范的标准 Tool 描述 JSON
  Map<String, dynamic> toMcpSchema() {
    return {
      'name': name,
      'description': description,
      'inputSchema': inputSchema,
    };
  }

  @override
  String toString() => 'McpToolDefinition(name: $name, category: $category)';
}
