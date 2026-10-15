import 'dart:io';

/// 终端输出行类型。
enum TerminalLineType { stdout, stderr, input, info }

/// 单行终端输出，支持普通文本与延迟本地化文案。
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

/// 单个设备终端会话状态。
class AdbTerminalSession {
  final String id;
  final String deviceId;
  final List<TerminalLine> lines;
  final List<String> commandHistory;
  final int historyIndex;
  final Process? process;
  final bool isRunning;

  /// 是否为鸿蒙设备会话，决定底层走 hdc 还是 adb。
  final bool isHarmony;

  const AdbTerminalSession({
    required this.id,
    required this.deviceId,
    required this.lines,
    required this.commandHistory,
    required this.historyIndex,
    this.process,
    required this.isRunning,
    this.isHarmony = false,
  });

  AdbTerminalSession copyWith({
    String? id,
    String? deviceId,
    List<TerminalLine>? lines,
    List<String>? commandHistory,
    int? historyIndex,
    Process? process,
    bool clearProcess = false,
    bool? isRunning,
    bool? isHarmony,
  }) {
    return AdbTerminalSession(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      lines: lines ?? this.lines,
      commandHistory: commandHistory ?? this.commandHistory,
      historyIndex: historyIndex ?? this.historyIndex,
      process: clearProcess ? null : process ?? this.process,
      isRunning: isRunning ?? this.isRunning,
      isHarmony: isHarmony ?? this.isHarmony,
    );
  }
}

/// 按设备隔离的终端整体状态。
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
