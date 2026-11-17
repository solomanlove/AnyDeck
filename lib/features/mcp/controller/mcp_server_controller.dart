import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/mcp/mcp_server.dart';
import '../../../core/mcp/models/mcp_server_config.dart';
import '../../../core/mcp/models/mcp_tool_definition.dart';
import '../../../core/mcp/registry/mcp_tool_registry.dart';
import '../../../core/mcp/registry/mcp_registry_factory.dart';
import '../../../core/ios/ios_mirror_service.dart';
import '../../../core/providers/app_providers.dart';
import 'mcp_audit_log_controller.dart';

/// MCP 服务状态数据模型
class McpServerState {
  final bool isRunning;
  final String statusText;
  final McpServerConfig config;
  final List<McpToolDefinition> registeredTools;
  final int totalRequestsCount;
  final String? lastError;

  const McpServerState({
    required this.isRunning,
    required this.statusText,
    required this.config,
    required this.registeredTools,
    this.totalRequestsCount = 0,
    this.lastError,
  });

  McpServerState copyWith({
    bool? isRunning,
    String? statusText,
    McpServerConfig? config,
    List<McpToolDefinition>? registeredTools,
    int? totalRequestsCount,
    String? lastError,
  }) {
    return McpServerState(
      isRunning: isRunning ?? this.isRunning,
      statusText: statusText ?? this.statusText,
      config: config ?? this.config,
      registeredTools: registeredTools ?? this.registeredTools,
      totalRequestsCount: totalRequestsCount ?? this.totalRequestsCount,
      lastError: lastError,
    );
  }
}

/// MCP 服务端状态控制器
class McpServerNotifier extends Notifier<McpServerState> {
  static const String _prefsKey = 'anydeck_mcp_config_v1';
  McpServer? _server;
  late McpToolRegistry _registry;

  @override
  McpServerState build() {
    ref.onDispose(() { unawaited(_server?.stop()); });
    // 异步初始化配置与工具注册
    Future.microtask(_init);

    return const McpServerState(
      isRunning: false,
      statusText: '未启动',
      config: McpServerConfig(),
      registeredTools: [],
    );
  }

  Future<void> _init() async {
    // 1. 注册核心设备与控制 Tools
    _registry = McpRegistryFactory(
      adb: ref.read(adbServiceProvider), hdc: ref.read(hdcServiceProvider),
      iosDevices: ref.read(iosDeviceServiceProvider),
      iosCommands: ref.read(iosCommandServiceProvider),
    ).create();

    // 2. 完整读取并持久化凭据后才能启动；失败时保留旧配置且不开放入口。
    late McpServerConfig config;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString(_prefsKey);
      config = savedJson == null || savedJson.isEmpty
          ? const McpServerConfig()
          : McpServerConfig.fromJson(jsonDecode(savedJson) as Map<String, dynamic>);
      final tokens = Map<String, String>.from(config.platformTokens);
      for (final platform in ['android', 'harmony', 'ios']) {
        if (tokens[platform]?.isNotEmpty != true) tokens[platform] = _newToken();
      }
      config = config.copyWith(platformTokens: tokens);
      if (!await prefs.setString(_prefsKey, jsonEncode(config.toJson()))) {
        throw StateError('MCP preferences write failed');
      }
    } catch (_) {
      if (ref.mounted) {
        state = state.copyWith(statusText: '启动失败', lastError: 'mcpConfigStorageError');
      }
      return;
    }

    if (!ref.mounted) return;

    await ref.read(mcpAuditLogProvider.notifier).ready;
    if (!ref.mounted) return;

    // 3. 构造 Server 实例
    _server = McpServer(
      registry: _registry,
      config: config,
      onAuditLog: ({
        required String method,
        required String? toolName,
        required Map<String, dynamic>? arguments,
        required bool isSuccess,
        required String? errorMessage,
        required int durationMs,
      }) {
        ref.read(mcpAuditLogProvider.notifier).recordLog(
              method: method,
              toolName: toolName,
              arguments: arguments,
              isSuccess: isSuccess,
              errorMessage: errorMessage,
              durationMs: durationMs,
            );
        state = state.copyWith(totalRequestsCount: state.totalRequestsCount + 1);
      },
    );

    state = state.copyWith(
      config: config,
      registeredTools: _registry.getAllTools(),
    );

    // 若配置开启了 SSE 且默认自动运行，可自动拉起
    if (config.enableSse) {
      await startServer();
    }
  }

  /// 启动 MCP 服务
  Future<void> startServer() async {
    if (_server == null) return;
    try {
      state = state.copyWith(statusText: '正在启动...');
      await _server!.startSse(customConfig: state.config);
      final newConfig = state.config.copyWith(enableSse: true);
      state = state.copyWith(
        isRunning: true,
        statusText: '运行中 (${state.config.host}:${state.config.port})',
        config: newConfig,
        lastError: null,
      );
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, jsonEncode(newConfig.toJson()));
      } catch (_) {}
    } catch (e) {
      state = state.copyWith(
        isRunning: false,
        statusText: '启动失败',
        lastError: e.toString(),
      );
    }
  }

  /// 停止 MCP 服务
  Future<void> stopServer() async {
    if (_server == null) return;
    try {
      await _server!.stop();
      await ref.read(mcpAuditLogProvider.notifier).flush();
      final newConfig = state.config.copyWith(enableSse: false);
      state = state.copyWith(
        isRunning: false,
        statusText: '已停止',
        config: newConfig,
      );
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, jsonEncode(newConfig.toJson()));
      } catch (_) {}
    } catch (e) {
      state = state.copyWith(lastError: e.toString());
    }
  }

  /// 更新服务器配置并保存
  Future<void> updateConfig(McpServerConfig newConfig) async {
    final wasRunning = state.isRunning;
    final old = state.config;
    final restart = old.host != newConfig.host || old.port != newConfig.port ||
        old.enableAuth != newConfig.enableAuth || old.authToken != newConfig.authToken;
    if (wasRunning && restart) {
      await stopServer();
    }
    _server?.config = newConfig;

    state = state.copyWith(config: newConfig);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(newConfig.toJson()));
    } catch (_) {}

    if (wasRunning && restart) {
      await startServer();
    }
  }

  /// 平台凭据仅在用户主动复制配置时输出，支持单独撤销与轮换。
  Future<void> setPlatformEnabled(String platform, bool enabled) async {
    final disabled = {...state.config.disabledPlatforms};
    enabled ? disabled.remove(platform) : disabled.add(platform);
    await updateConfig(state.config.copyWith(disabledPlatforms: disabled));
  }

  Future<void> rotatePlatformToken(String platform) async {
    await updateConfig(state.config.copyWith(platformTokens: {
      ...state.config.platformTokens, platform: _newToken(),
    }));
  }

  String _newToken() => base64UrlEncode(List<int>.generate(32, (_) => Random.secure().nextInt(256)));

  /// 切换指定工具的启用/禁用状态
  Future<void> toggleTool(String toolName, bool enabled) async {
    final currentDisabled = Set<String>.from(state.config.disabledToolNames);
    if (enabled) {
      currentDisabled.remove(toolName);
    } else {
      currentDisabled.add(toolName);
    }
    final newConfig = state.config.copyWith(disabledToolNames: currentDisabled);
    await updateConfig(newConfig);
  }
}

/// MCP 服务全局 NotifierProvider
final mcpServerProvider =
    NotifierProvider<McpServerNotifier, McpServerState>(
  McpServerNotifier.new,
);
