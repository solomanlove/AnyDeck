/// JSON-RPC 2.0 响应数据模型
class McpResponse {
  final String jsonrpc;
  final dynamic id;
  final dynamic result;
  final McpError? error;

  const McpResponse({
    this.jsonrpc = '2.0',
    required this.id,
    this.result,
    this.error,
  });

  /// 快速构造成功响应
  factory McpResponse.success({
    required dynamic id,
    required dynamic result,
  }) {
    return McpResponse(
      id: id,
      result: result,
    );
  }

  /// 快速构造 Tool 执行结果成功响应
  factory McpResponse.toolResult({
    required dynamic id,
    required String text,
    bool isError = false,
    Map<String, dynamic>? extraData,
  }) {
    final content = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text': text,
      }
    ];

    final result = <String, dynamic>{
      'content': content,
      'isError': isError,
    };

    if (extraData != null) {
      result['data'] = extraData;
    }

    return McpResponse(
      id: id,
      result: result,
    );
  }

  /// 快速构造错误响应
  factory McpResponse.error({
    required dynamic id,
    required int code,
    required String message,
    dynamic data,
  }) {
    return McpResponse(
      id: id,
      error: McpError(code: code, message: message, data: data),
    );
  }

  /// 序列化为 JSON Map
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'jsonrpc': jsonrpc,
      'id': id,
    };
    if (error != null) {
      map['error'] = error!.toJson();
    } else {
      map['result'] = result;
    }
    return map;
  }

  @override
  String toString() => 'McpResponse(id: $id, isError: ${error != null})';
}

/// JSON-RPC 2.0 错误模型
class McpError {
  final int code;
  final String message;
  final dynamic data;

  const McpError({
    required this.code,
    required this.message,
    this.data,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'code': code,
      'message': message,
    };
    if (data != null) {
      map['data'] = data;
    }
    return map;
  }

  // 标准 JSON-RPC 错误码定义
  static const int parseError = -32700;
  static const int invalidRequest = -32600;
  static const int methodNotFound = -32601;
  static const int invalidParams = -32602;
  static const int internalError = -32603;
  static const int unauthorized = -32001;
  static const int toolExecutionError = -32002;
  static const int dangerousOperationBlocked = -32003;
}
