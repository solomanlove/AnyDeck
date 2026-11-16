part of 'app_settings_controller.dart';

const toolPathChannelMethod = 'update_tool_path';

/// 核心 CLI 路径修改收口到设置 Controller，持久化后再同步其他 Engine。
mixin ToolPathSettings
    on Notifier<AppSettings>, SettingsBroadcast, ReceiverNameSettings {
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
