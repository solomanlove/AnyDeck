/// MCP 安全防御与高危操作拦截器
class McpSecurityGuard {
  /// 高危命令模式黑名单 (针对 execute_shell)
  static final List<RegExp> _dangerousShellPatterns = [
    RegExp(r'\brm\s+-[rfRF]+\s+/(?:\s|$|\*)', caseSensitive: false),
    RegExp(r'\brm\s+-[rfRF]+\s+/data(?:\s|$|\*)', caseSensitive: false),
    RegExp(r'\brm\s+-[rfRF]+\s+/system(?:\s|$|\*)', caseSensitive: false),
    RegExp(r'\bmkfs\b', caseSensitive: false),
    RegExp(r'\bfastboot\s+flash\b', caseSensitive: false),
    RegExp(r'\brecovery\s+--wipe_data\b', caseSensitive: false),
    RegExp(r'\bdd\s+if=.*of=/dev/block\b', caseSensitive: false),
    RegExp(r'\bformat\s+[a-z0-9/:]+', caseSensitive: false),
  ];

  /// 检查 Shell 命令是否包含致命危险指令
  ///
  /// 返回 null 表示安全通过；若包含危险指令则返回拦截原因字符串
  static String? checkDangerousShellCommand(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      return '命令内容不能为空';
    }

    for (final pattern in _dangerousShellPatterns) {
      if (pattern.hasMatch(trimmed)) {
        return '安全拦截：检测到高危系统破坏性命令 [$trimmed]，已自动阻止执行。';
      }
    }

    return null;
  }

  /// 检查特定工具调用是否允许执行
  static String? checkToolExecutionAllowed({
    required String toolName,
    required bool isDangerous,
    required bool enableDangerousGuard,
    required Set<String> disabledTools,
  }) {
    if (disabledTools.contains(toolName)) {
      return '工具 [$toolName] 已在 AnyDeck 设置中被禁用。';
    }

    return null;
  }
}
