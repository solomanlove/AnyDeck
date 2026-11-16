part of 'app_settings_controller.dart';

const toolPathChannelMethod = 'update_tool_path';
const resolveToolPathsChannelMethod = 'resolve_tool_paths';

/// 核心 CLI 路径修改收口到设置 Controller，持久化后再同步其他 Engine。
mixin ToolPathSettings
    on Notifier<AppSettings>, SettingsBroadcast, ReceiverNameSettings {
  final Map<String, int> _toolPathRevisions = {};

  /// 通道注册完成后拉取主窗口快照，补齐子 Engine 初始化阶段错过的广播。
  Future<void> _initializeSettingsSynchronization(
    Future<dynamic> Function(MethodCall) handler,
  ) async {
    try {
      final currentId = ref.read(windowIdProvider);
      if (currentId.isNotEmpty) {
        ref.onDispose(() => SubWindowMethodDispatcher.removeHandler(handler));
      }
      await _setupSettingsMethodHandler(currentId, handler);
      await _settingsLoaded;
      if (!ref.mounted || ref.read(windowIdProvider).isEmpty) return;
      final revisions = Map<String, int>.of(_toolPathRevisions);
      final snapshot = await AppSettingsController._mainSettingsChannel
          .invokeMethod<Object?>(resolveToolPathsChannelMethod)
          .timeout(const Duration(seconds: 15));
      if (!ref.mounted || snapshot is! Map) return;
      for (final tool in configurableToolNames) {
        final path = snapshot[tool] ?? '';
        // 在请求期间收到的实时更新或本地保存优先于可能较旧的完整快照。
        if (path is String && _toolPathRevisions[tool] == revisions[tool]) {
          _applyToolPath(tool, path);
        }
      }
    } catch (error) {
      debugPrint('Failed to initialize settings synchronization: $error');
    }
  }

  Future<Map<String, String>> _toolPathsSnapshot() async {
    await _settingsLoaded;
    return Map<String, String>.of(state.toolPaths);
  }

  Future<void> setToolPath(
    String toolName,
    String path, {
    bool broadcast = true,
  }) async {
    await _settingsLoaded;
    final clean = await validateToolPath(toolName, path);
    final preferences = await SharedPreferences.getInstance();
    final key = toolPathPreferenceKey(toolName);
    final saved = clean.isEmpty
        ? await preferences.remove(key)
        : await preferences.setString(key, clean);
    if (!saved) throw StateError('toolPathSaveFailed');
    if (!ref.mounted) return;
    _applyToolPath(toolName, clean);
    if (broadcast) {
      try {
        await _broadcastSettingChange(toolPathChannelMethod, {
          'tool': toolName,
          'path': clean,
        });
      } catch (error) {
        debugPrint('Failed to broadcast tool path change: $error');
      }
    }
  }

  /// 接收端仅应用快照，不再次写入 Preference，避免广播旧值覆盖后续修改。
  Future<void> _receiveToolPath(Object? value) async {
    if (value is! Map) return;
    final tool = value['tool'];
    final path = value['path'];
    if (tool is! String ||
        path is! String ||
        !configurableToolNames.contains(tool)) {
      return;
    }
    await _settingsLoaded;
    if (ref.mounted) _applyToolPath(tool, path);
  }

  void _applyToolPath(String tool, String path) {
    _toolPathRevisions[tool] = (_toolPathRevisions[tool] ?? 0) + 1;
    final paths = Map<String, String>.of(state.toolPaths);
    if (path.isEmpty) {
      paths.remove(tool);
    } else {
      paths[tool] = path;
    }
    replaceUserToolPaths(paths);
    state = state.copyWith(toolPaths: Map.unmodifiable(paths));
  }
}
