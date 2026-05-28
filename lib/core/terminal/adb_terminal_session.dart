import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../process/tool_path_resolver.dart';

/// 终端单行输出类型
enum TerminalLineType { stdout, stderr, input, info }

/// 终端单行输出数据
class TerminalLine {
  final String text;
  final TerminalLineType type;

  const TerminalLine({required this.text, required this.type});
}

/// 终端会话状态模型
class AdbTerminalSession {
  final String id;
  final String name;
  final String deviceId;
  final List<TerminalLine> lines;
  final List<String> commandHistory;
  final int historyIndex;
  final Process? process;
  final bool isRunning;

  const AdbTerminalSession({
    required this.id,
    required this.name,
    required this.deviceId,
    required this.lines,
    required this.commandHistory,
    required this.historyIndex,
    this.process,
    required this.isRunning,
  });

  AdbTerminalSession copyWith({
    String? id,
    String? name,
    String? deviceId,
    List<TerminalLine>? lines,
    List<String>? commandHistory,
    int? historyIndex,
    Process? process,
    bool? isRunning,
  }) {
    return AdbTerminalSession(
      id: id ?? this.id,
      name: name ?? this.name,
      deviceId: deviceId ?? this.deviceId,
      lines: lines ?? this.lines,
      commandHistory: commandHistory ?? this.commandHistory,
      historyIndex: historyIndex ?? this.historyIndex,
      process: process ?? this.process,
      isRunning: isRunning ?? this.isRunning,
    );
  }
}

/// 终端整体状态 (按设备ID隔离)
class AdbTerminalState {
  final Map<String, List<AdbTerminalSession>> deviceSessions;
  final Map<String, String?> activeSessionIds;

  const AdbTerminalState({
    this.deviceSessions = const {},
    this.activeSessionIds = const {},
  });

  AdbTerminalState copyWith({
    Map<String, List<AdbTerminalSession>>? deviceSessions,
    Map<String, String?>? activeSessionIds,
  }) {
    return AdbTerminalState(
      deviceSessions: deviceSessions ?? this.deviceSessions,
      activeSessionIds: activeSessionIds ?? this.activeSessionIds,
    );
  }

  List<AdbTerminalSession> getSessions(String deviceId) {
    return deviceSessions[deviceId] ?? [];
  }

  String? getActiveSessionId(String deviceId) {
    return activeSessionIds[deviceId];
  }

  AdbTerminalSession? getActiveSession(String deviceId) {
    final activeId = getActiveSessionId(deviceId);
    if (activeId == null) return null;
    final sessions = getSessions(deviceId);
    final index = sessions.indexWhere((s) => s.id == activeId);
    return index != -1 ? sessions[index] : null;
  }
}

/// 终端会话管理器 Notifier
class AdbTerminalNotifier extends Notifier<AdbTerminalState> {
  @override
  AdbTerminalState build() {
    ref.onDispose(() {
      // 销毁时停止所有设备的所有交互式进程
      for (final sessions in state.deviceSessions.values) {
        for (final session in sessions) {
          session.process?.kill();
        }
      }
    });
    return const AdbTerminalState();
  }

  /// 创建并启动一个新的终端会话
  Future<void> createSession(String deviceId) async {
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final currentSessions = state.getSessions(deviceId);
    final name = '终端 ${currentSessions.length + 1}';

    final session = AdbTerminalSession(
      id: sessionId,
      name: name,
      deviceId: deviceId,
      lines: [
        const TerminalLine(
          text: '正在初始化 ADB shell 会话...\n',
          type: TerminalLineType.info,
        ),
      ],
      commandHistory: [],
      historyIndex: -1,
      isRunning: true,
    );

    final updatedSessionsMap = Map<String, List<AdbTerminalSession>>.from(
      state.deviceSessions,
    );
    updatedSessionsMap[deviceId] = [...currentSessions, session];

    final updatedActiveIdsMap = Map<String, String?>.from(
      state.activeSessionIds,
    );
    updatedActiveIdsMap[deviceId] = sessionId;

    state = state.copyWith(
      deviceSessions: updatedSessionsMap,
      activeSessionIds: updatedActiveIdsMap,
    );

    try {
      final adbPath = resolveToolPath('adb');
      final process = await Process.start(adbPath, ['-s', deviceId, 'shell']);

      _updateSession(deviceId, sessionId, (s) => s.copyWith(process: process));

      // 监听 stdout
      process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen((
        data,
      ) {
        _appendOutput(deviceId, sessionId, data, TerminalLineType.stdout);
      });

      // 监听 stderr
      process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((
        data,
      ) {
        _appendOutput(deviceId, sessionId, data, TerminalLineType.stderr);
      });

      // 进程退出处理
      process.exitCode.then((code) {
        _appendOutput(
          deviceId,
          sessionId,
          '\n[进程已终止，退出码: $code]',
          TerminalLineType.info,
        );
        _updateSession(
          deviceId,
          sessionId,
          (s) => s.copyWith(isRunning: false, process: null),
        );
      });
    } on Object catch (e) {
      _appendOutput(deviceId, sessionId, '\n启动终端失败: $e', TerminalLineType.info);
      _updateSession(
        deviceId,
        sessionId,
        (s) => s.copyWith(isRunning: false, process: null),
      );
    }
  }

  /// 切换当前活动的终端标签页
  void selectSession(String deviceId, String sessionId) {
    final updatedActiveIdsMap = Map<String, String?>.from(
      state.activeSessionIds,
    );
    updatedActiveIdsMap[deviceId] = sessionId;
    state = state.copyWith(activeSessionIds: updatedActiveIdsMap);
  }

  /// 关闭一个终端会话并杀死其底层进程
  Future<void> closeSession(String deviceId, String sessionId) async {
    final sessions = state.getSessions(deviceId);
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index == -1) return;

    final session = sessions[index];
    session.process?.kill();

    final updatedSessions = sessions.where((s) => s.id != sessionId).toList();

    final updatedSessionsMap = Map<String, List<AdbTerminalSession>>.from(
      state.deviceSessions,
    );
    updatedSessionsMap[deviceId] = updatedSessions;

    final updatedActiveIdsMap = Map<String, String?>.from(
      state.activeSessionIds,
    );
    if (state.getActiveSessionId(deviceId) == sessionId) {
      updatedActiveIdsMap[deviceId] = updatedSessions.isNotEmpty
          ? updatedSessions.last.id
          : null;
    }

    state = state.copyWith(
      deviceSessions: updatedSessionsMap,
      activeSessionIds: updatedActiveIdsMap,
    );
  }

  /// 发送命令字符串到当前会话的 shell 进程 stdin
  void sendCommand(String deviceId, String sessionId, String command) {
    final sessions = state.getSessions(deviceId);
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index == -1) return;

    final session = sessions[index];
    if (session.process == null || !session.isRunning) {
      _appendOutput(
        deviceId,
        sessionId,
        '\n[当前终端已离线，无法发送命令]',
        TerminalLineType.info,
      );
      return;
    }

    session.process!.stdin.write('$command\n');

    final newHistory = [...session.commandHistory, command];
    final newLines = [
      ...session.lines,
      TerminalLine(text: command, type: TerminalLineType.input),
    ];

    _updateSession(deviceId, sessionId, (s) {
      return s.copyWith(
        commandHistory: newHistory,
        historyIndex: newHistory.length,
        lines: newLines,
      );
    });
  }

  /// 发送 Ctrl+C (SIGINT) 信号到当前进程
  void sendCtrlC(String deviceId, String sessionId) {
    final sessions = state.getSessions(deviceId);
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index == -1) return;

    final session = sessions[index];
    if (session.process != null && session.isRunning) {
      session.process!.stdin.add([3]); // ASCII 3 represents Ctrl+C
      _appendOutput(deviceId, sessionId, '^C', TerminalLineType.info);
    }
  }

  /// 重启终端进程
  Future<void> restartSession(String deviceId, String sessionId) async {
    final sessions = state.getSessions(deviceId);
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index == -1) return;

    final session = sessions[index];
    session.process?.kill();

    _updateSession(
      deviceId,
      sessionId,
      (s) => s.copyWith(
        lines: [
          const TerminalLine(
            text: '正在重新连接 shell...\n',
            type: TerminalLineType.info,
          ),
        ],
        isRunning: true,
        process: null,
      ),
    );

    try {
      final adbPath = resolveToolPath('adb');
      final process = await Process.start(adbPath, ['-s', deviceId, 'shell']);

      _updateSession(deviceId, sessionId, (s) => s.copyWith(process: process));

      process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen((
        data,
      ) {
        _appendOutput(deviceId, sessionId, data, TerminalLineType.stdout);
      });

      process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((
        data,
      ) {
        _appendOutput(deviceId, sessionId, data, TerminalLineType.stderr);
      });

      process.exitCode.then((code) {
        _appendOutput(
          deviceId,
          sessionId,
          '\n[进程已终止，退出码: $code]',
          TerminalLineType.info,
        );
        _updateSession(
          deviceId,
          sessionId,
          (s) => s.copyWith(isRunning: false, process: null),
        );
      });
    } on Object catch (e) {
      _appendOutput(deviceId, sessionId, '\n重连终端失败: $e', TerminalLineType.info);
      _updateSession(
        deviceId,
        sessionId,
        (s) => s.copyWith(isRunning: false, process: null),
      );
    }
  }

  /// 清空终端输出缓冲区
  void clearBuffer(String deviceId, String sessionId) {
    _updateSession(deviceId, sessionId, (s) => s.copyWith(lines: []));
  }

  /// 历史命令上下翻页
  String? getHistoryCommand(
    String deviceId,
    String sessionId,
    bool isUp,
    String currentInput,
  ) {
    final sessions = state.getSessions(deviceId);
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index == -1) return null;

    final session = sessions[index];
    if (session.commandHistory.isEmpty) return null;

    int newIndex = session.historyIndex;
    if (isUp) {
      newIndex = newIndex - 1;
      if (newIndex < 0) newIndex = 0;
    } else {
      newIndex = newIndex + 1;
      if (newIndex >= session.commandHistory.length) {
        newIndex = session.commandHistory.length;
        _updateSession(
          deviceId,
          sessionId,
          (s) => s.copyWith(historyIndex: newIndex),
        );
        return '';
      }
    }

    _updateSession(
      deviceId,
      sessionId,
      (s) => s.copyWith(historyIndex: newIndex),
    );
    return session.commandHistory[newIndex];
  }

  /// 辅助更新单个会话的数据
  void _updateSession(
    String deviceId,
    String sessionId,
    AdbTerminalSession Function(AdbTerminalSession) updater,
  ) {
    final sessions = state.getSessions(deviceId);
    final updatedSessions = sessions.map((s) {
      if (s.id == sessionId) {
        return updater(s);
      }
      return s;
    }).toList();

    final updatedSessionsMap = Map<String, List<AdbTerminalSession>>.from(
      state.deviceSessions,
    );
    updatedSessionsMap[deviceId] = updatedSessions;

    state = state.copyWith(deviceSessions: updatedSessionsMap);
  }

  /// 追加输出数据
  void _appendOutput(
    String deviceId,
    String sessionId,
    String chunk,
    TerminalLineType type,
  ) {
    final sessions = state.getSessions(deviceId);
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index == -1) return;

    final session = sessions[index];
    final currentLines = List<TerminalLine>.from(session.lines);

    final cleanChunk = chunk.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
    if (cleanChunk.isEmpty) return;

    final newParts = cleanChunk.split(RegExp(r'\r\n|\n|\r'));

    if (currentLines.isEmpty) {
      currentLines.add(TerminalLine(text: '', type: type));
    }

    final lastLine = currentLines.last;
    if (lastLine.type == type || lastLine.text.isEmpty) {
      currentLines[currentLines.length - 1] = TerminalLine(
        text: lastLine.text + newParts[0],
        type: type,
      );
    } else {
      currentLines.add(TerminalLine(text: newParts[0], type: type));
    }

    for (int i = 1; i < newParts.length; i++) {
      currentLines.add(TerminalLine(text: newParts[i], type: type));
    }

    if (currentLines.length > 1500) {
      currentLines.removeRange(0, currentLines.length - 1500);
    }

    _updateSession(deviceId, sessionId, (s) => s.copyWith(lines: currentLines));
  }
}

/// 常用收藏命令模型
class FavoriteCommand {
  final String id;
  final String title;
  final String command;
  final bool isCustom;

  const FavoriteCommand({
    required this.id,
    required this.title,
    required this.command,
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'command': command,
    'isCustom': isCustom,
  };

  factory FavoriteCommand.fromJson(Map<String, dynamic> json) =>
      FavoriteCommand(
        id: json['id'] as String,
        title: json['title'] as String,
        command: json['command'] as String,
        isCustom: json['isCustom'] as bool? ?? false,
      );
}

/// 收藏命令管理器 Notifier
class FavoriteCommandsNotifier extends Notifier<List<FavoriteCommand>> {
  static const _prefsKey = 'terminal.favorites';
  static const _deletedDefaultsKey = 'terminal.favorites.deleted_defaults';

  final List<FavoriteCommand> _defaultCommands = [
    const FavoriteCommand(
      id: 'default_packages',
      title: '列出所有已安装包',
      command: 'pm list packages',
    ),
    const FavoriteCommand(
      id: 'default_focus',
      title: '获取当前前台 Activity',
      command: 'dumpsys window | grep mCurrentFocus',
    ),
    const FavoriteCommand(
      id: 'default_screenshot',
      title: '手机屏幕截图',
      command: 'screencap -p /sdcard/screenshot.png',
    ),
    const FavoriteCommand(
      id: 'default_version',
      title: '获取系统 Android 版本',
      command: 'getprop ro.build.version.release',
    ),
    const FavoriteCommand(
      id: 'default_logcat_dump',
      title: '导出当前日志缓冲区',
      command: 'logcat -d',
    ),
    const FavoriteCommand(
      id: 'default_ip',
      title: '查看手机网卡 IP 信息',
      command: 'ip addr show wlan0',
    ),
  ];

  @override
  List<FavoriteCommand> build() {
    _loadFavorites();
    return _defaultCommands;
  }

  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customJson = prefs.getStringList(_prefsKey);
      final deletedDefaults = prefs.getStringList(_deletedDefaultsKey) ?? [];

      final activeDefaults = _defaultCommands
          .where((cmd) => !deletedDefaults.contains(cmd.id))
          .toList();

      if (customJson == null) {
        state = activeDefaults;
        return;
      }

      final customList = customJson
          .map((item) {
            try {
              return FavoriteCommand.fromJson(
                jsonDecode(item) as Map<String, dynamic>,
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<FavoriteCommand>()
          .toList();

      state = [...activeDefaults, ...customList];
    } catch (_) {}
  }

  Future<void> addFavorite(String title, String command) async {
    final newCmd = FavoriteCommand(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title.trim(),
      command: command.trim(),
      isCustom: true,
    );

    state = [...state, newCmd];
    await _saveCustomFavorites();
  }

  Future<void> deleteFavorite(String id) async {
    final cmdToDelete = state.firstWhere(
      (cmd) => cmd.id == id,
      orElse: () => const FavoriteCommand(id: '', title: '', command: ''),
    );
    if (cmdToDelete.id.isEmpty) return;

    state = state.where((cmd) => cmd.id != id).toList();

    if (!cmdToDelete.isCustom) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final deletedDefaults = prefs.getStringList(_deletedDefaultsKey) ?? [];
        if (!deletedDefaults.contains(id)) {
          deletedDefaults.add(id);
          await prefs.setStringList(_deletedDefaultsKey, deletedDefaults);
        }
      } catch (_) {}
    } else {
      await _saveCustomFavorites();
    }
  }

  Future<void> resetFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_deletedDefaultsKey);
      await _loadFavorites();
    } catch (_) {}
  }

  Future<void> _saveCustomFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customList = state.where((cmd) => cmd.isCustom).toList();
      final jsonList = customList
          .map((cmd) => jsonEncode(cmd.toJson()))
          .toList();
      await prefs.setStringList(_prefsKey, jsonList);
    } catch (_) {}
  }
}
