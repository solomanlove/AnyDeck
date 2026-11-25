/// 从 MCP 响应提取的可持久化元数据，避免保留设备输出和异常正文。
class McpAuditResponseSummary {
  const McpAuditResponseSummary({
    required this.protocolVersion,
    this.supportedVersions = const [],
    this.itemCount,
    this.errorCode,
    this.isToolError = false,
  });

  final String protocolVersion;
  final List<String> supportedVersions;
  final int? itemCount;
  final int? errorCode;
  final bool isToolError;

  Map<String, dynamic> toJson() => {
    'protocolVersion': protocolVersion,
    if (supportedVersions.isNotEmpty) 'supportedVersions': supportedVersions,
    if (itemCount != null) 'itemCount': itemCount,
    if (errorCode != null) 'errorCode': errorCode,
    if (isToolError) 'isToolError': true,
  };

  factory McpAuditResponseSummary.fromJson(Map<String, dynamic> json) =>
      McpAuditResponseSummary(
        protocolVersion: json['protocolVersion'] as String,
        supportedVersions:
            (json['supportedVersions'] as List?)?.cast<String>() ?? const [],
        itemCount: json['itemCount'] as int?,
        errorCode: json['errorCode'] as int?,
        isToolError: json['isToolError'] == true,
      );
}
