import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/mcp/mcp_server.dart';
import '../../../core/mcp/models/mcp_server_config.dart';
import '../../../core/mcp/models/mcp_tool_definition.dart';
import '../../../core/mcp/registry/mcp_tool_registry.dart';
import '../../../core/mcp/tools/mcp_app_tools.dart';
import '../../../core/mcp/tools/mcp_device_tools.dart';
import '../../../core/mcp/tools/mcp_file_tools.dart';
import '../../../core/mcp/tools/mcp_log_tools.dart';
import '../../../core/mcp/tools/mcp_ui_tools.dart';
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
  final McpToolRegistry _registry = McpToolRegistry();

  @override
  McpServerState build() {
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
    final adbService = ref.read(adbServiceProvider);
    final deviceInfoService = ref.read(deviceInfoServiceProvider);
    final actionService = ref.read(deviceActionServiceProvider);
    final appService = ref.read(appManagementServiceProvider);
    final layoutService = ref.read(layoutInspectorServiceProvider);
    final fileManagerService = ref.read(fileManagerServiceProvider);

    final deviceTools = McpDeviceTools(
      adbService: adbService,
      deviceInfoService: deviceInfoService,
    );
    final uiTools = McpUiTools(
      adbService: adbService,
      actionService: actionService,
      layoutService: layoutService,
    );
    final appTools = McpAppTools(appService: appService);
    final logTools = McpLogTools(adbService: adbService);
    final fileTools = McpFileTools(
      adbService: adbService,
      fileManagerService: fileManagerService,
    );

    _registry.registerAll(deviceTools.getTools());
    _registry.registerAll(uiTools.getTools());
    _registry.registerAll(appTools.getTools());
    _registry.registerAll(logTools.getTools());
    _registry.registerAll(fileTools.getTools());

    // 2. 从本地缓存读取配置
    var config = const McpServerConfig();
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString(_prefsKey);
      if (savedJson != null && savedJson.isNotEmpty) {
        config = McpServerConfig.fromJson(jsonDecode(savedJson) as Map<String, dynamic>);
      }
    } catch (_) {}

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
    if (wasRunning) {
      await stopServer();
    }

    state = state.copyWith(config: newConfig);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(newConfig.toJson()));
    } catch (_) {}

    if (wasRunning) {
      await startServer();
    }
  }

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
