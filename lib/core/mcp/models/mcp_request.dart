/// JSON-RPC 2.0 请求数据模型
class McpRequest {
  final String jsonrpc;
  final dynamic id;
  final String method;
  final Map<String, dynamic>? params;

  const McpRequest({
    this.jsonrpc = '2.0',
    required this.id,
    required this.method,
    this.params,
  });

  /// 从原始 Map 构建 JSON-RPC 请求
  factory McpRequest.fromJson(Map<String, dynamic> json) {
    return McpRequest(
      jsonrpc: json['jsonrpc'] as String? ?? '2.0',
      id: json['id'],
      method: json['method'] as String? ?? '',
      params: json['params'] is Map<String, dynamic> ? json['params'] as Map<String, dynamic> : null,
    );
  }

  /// 序列化为 JSON Map
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'jsonrpc': jsonrpc,
      'method': method,
    };
    if (id != null) {
      map['id'] = id;
    }
    if (params != null) {
      map['params'] = params;
    }
    return map;
  }

  /// 是否为 JSON-RPC 2.0 通知 (无 id 或以 notifications/ 开头)
  bool get isNotification => id == null || method.startsWith('notifications/');

  @override
  String toString() => 'McpRequest(id: $id, method: $method)';
}
