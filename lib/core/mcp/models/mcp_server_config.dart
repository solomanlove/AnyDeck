/// MCP Server 运行配置模型
class McpServerConfig {
  /// 是否启用内置 SSE HTTP 服务
  final bool enableSse;

  /// HTTP 服务监听主机 (默认 127.0.0.1 确保安全)
  final String host;

  /// HTTP 服务监听端口 (默认 8765)
  final int port;

  /// 是否启用 Token 鉴权保护
  final bool enableAuth;

  /// 鉴权 API Token (空则无需鉴权)
  final String authToken;

  /// 是否拦截危险操作 (高危 Shell、重置、卸载等)
  final bool enableDangerousOperationGuard;

  /// 允许启用的工具分类白名单 (空表示全量允许)
  final Set<String> enabledCategories;

  /// 单独禁用的工具名称列表
  final Set<String> disabledToolNames;

  /// 兼容入口可显式开启；新配置默认关闭，旧配置迁移保留。
  final bool enableLegacy;

  /// 平台入口独立禁用和凭据；空 Token 时平台入口不可调用。
  final Set<String> disabledPlatforms;
  final Map<String, String> platformTokens;

  const McpServerConfig({
    this.enableLegacy = false,
    this.disabledPlatforms = const {},
    this.platformTokens = const {},
    this.enableSse = false,
    this.host = '127.0.0.1',
    this.port = 8765,
    this.enableAuth = false,
    this.authToken = '',
    this.enableDangerousOperationGuard = true,
    this.enabledCategories = const {},
    this.disabledToolNames = const {},
  });

  McpServerConfig copyWith({
    bool? enableLegacy,
    Set<String>? disabledPlatforms,
    Map<String, String>? platformTokens,
    bool? enableSse,
    String? host,
    int? port,
    bool? enableAuth,
    String? authToken,
    bool? enableDangerousOperationGuard,
    Set<String>? enabledCategories,
    Set<String>? disabledToolNames,
  }) {
    return McpServerConfig(
      enableLegacy: enableLegacy ?? this.enableLegacy,
      disabledPlatforms: disabledPlatforms ?? this.disabledPlatforms,
      platformTokens: platformTokens ?? this.platformTokens,
      enableSse: enableSse ?? this.enableSse,
      host: host ?? this.host,
      port: port ?? this.port,
      enableAuth: enableAuth ?? this.enableAuth,
      authToken: authToken ?? this.authToken,
      enableDangerousOperationGuard:
          enableDangerousOperationGuard ?? this.enableDangerousOperationGuard,
      enabledCategories: enabledCategories ?? this.enabledCategories,
      disabledToolNames: disabledToolNames ?? this.disabledToolNames,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enableLegacy': enableLegacy,
      'disabledPlatforms': disabledPlatforms.toList(),
      'platformTokens': platformTokens,
      'enableSse': enableSse,
      'host': host,
      'port': port,
      'enableAuth': enableAuth,
      'authToken': authToken,
      'enableDangerousOperationGuard': enableDangerousOperationGuard,
      'enabledCategories': enabledCategories.toList(),
      'disabledToolNames': disabledToolNames.toList(),
    };
  }

  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    return McpServerConfig(
      enableLegacy: json['enableLegacy'] as bool? ?? true,
      disabledPlatforms: (json['disabledPlatforms'] as List<dynamic>?)
          ?.cast<String>().toSet() ?? const {},
      platformTokens: (json['platformTokens'] as Map<String, dynamic>?)
          ?.cast<String, String>() ?? const {},
      enableSse: json['enableSse'] as bool? ?? false,
      host: json['host'] as String? ?? '127.0.0.1',
      port: json['port'] as int? ?? 8765,
      enableAuth: json['enableAuth'] as bool? ?? false,
      authToken: json['authToken'] as String? ?? '',
      enableDangerousOperationGuard:
          json['enableDangerousOperationGuard'] as bool? ?? true,
      enabledCategories: (json['enabledCategories'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toSet() ??
          const {},
      disabledToolNames: (json['disabledToolNames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toSet() ??
          const {},
    );
  }
}
