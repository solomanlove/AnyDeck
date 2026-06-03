import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../process/tool_path_resolver.dart';

enum TerminalLineType { stdout, stderr, input, info }

class TerminalLine {
  final String text;
  final TerminalLineType type;
  final String? l10nKey;
  final Map<String, String> l10nArgs;

  const TerminalLine({
    required this.text,
    required this.type,
    this.l10nKey,
    this.l10nArgs = const {},
  });

  const TerminalLine.localized({
    required this.l10nKey,
    required this.type,
    this.l10nArgs = const {},
  }) : text = '';
}

/// 终端会话状态模型
class AdbTerminalSession {
  final String id;
  final String deviceId;
  final List<TerminalLine> lines;
  final List<String> commandHistory;
  final int historyIndex;
  final Process? process;
  final bool isRunning;

  const AdbTerminalSession({
    required this.id,
    required this.deviceId,
    required this.lines,
    required this.commandHistory,
    required this.historyIndex,
    this.process,
    required this.isRunning,
  });

  AdbTerminalSession copyWith({
    String? id,
    String? deviceId,
    List<TerminalLine>? lines,
    List<String>? commandHistory,
    int? historyIndex,
    Process? process,
    bool? isRunning,
  }) {
    return AdbTerminalSession(
      id: id ?? this.id,
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

    final session = AdbTerminalSession(
      id: sessionId,
      deviceId: deviceId,
      lines: [],
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
        _appendLocalizedOutput(
          deviceId,
          sessionId,
          'terminalProcessTerminated',
          TerminalLineType.info,
          args: {'code': '$code'},
        );
        _updateSession(
          deviceId,
          sessionId,
          (s) => s.copyWith(isRunning: false, process: null),
        );
      });
    } on Object catch (e) {
      _appendLocalizedOutput(
        deviceId,
        sessionId,
        'terminalStartFailed',
        TerminalLineType.info,
        args: {'error': '$e'},
      );
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
      _appendLocalizedOutput(
        deviceId,
        sessionId,
        'terminalOfflineCannotSend',
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
        lines: [],
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
        _appendLocalizedOutput(
          deviceId,
          sessionId,
          'terminalProcessTerminated',
          TerminalLineType.info,
          args: {'code': '$code'},
        );
        _updateSession(
          deviceId,
          sessionId,
          (s) => s.copyWith(isRunning: false, process: null),
        );
      });
    } on Object catch (e) {
      _appendLocalizedOutput(
        deviceId,
        sessionId,
        'terminalReconnectFailed',
        TerminalLineType.info,
        args: {'error': '$e'},
      );
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

  /// 追加应用内状态文案，交给 UI 根据当前语言渲染。
  void _appendLocalizedOutput(
    String deviceId,
    String sessionId,
    String key,
    TerminalLineType type, {
    Map<String, String> args = const {},
  }) {
    final sessions = state.getSessions(deviceId);
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index == -1) return;

    final session = sessions[index];
    final currentLines = List<TerminalLine>.from(session.lines)
      ..add(TerminalLine.localized(l10nKey: key, type: type, l10nArgs: args));

    if (currentLines.length > 1500) {
      currentLines.removeRange(0, currentLines.length - 1500);
    }

    _updateSession(deviceId, sessionId, (s) => s.copyWith(lines: currentLines));
  }
}
