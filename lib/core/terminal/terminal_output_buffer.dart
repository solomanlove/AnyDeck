part of 'adb_terminal_session.dart';

/// 限制终端输出暂存量，并按批次发布到会话状态。
mixin TerminalOutputBuffer on Notifier<AdbTerminalState> {
  static const _maxOutputLines = 1500;
  static const _maxLineLength = 16384;
  static const _maxHistoryCommands = 200;
  final Map<String, List<(String, TerminalLineType)>> _pendingOutput = {};
  final Map<String, Timer> _outputTimers = {};

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
    if (type == TerminalLineType.stdout || type == TerminalLineType.stderr) {
      final pending = _pendingOutput.putIfAbsent(sessionId, () => []);
      pending.add((
        chunk.length > 32768 ? chunk.substring(chunk.length - 32768) : chunk,
        type,
      ));
      if (pending.length > 128) {
        pending.removeRange(0, pending.length - 128);
      }
      _outputTimers.putIfAbsent(
        sessionId,
        () => Timer(
          const Duration(milliseconds: 100),
          () => _flushOutput(deviceId, sessionId),
        ),
      );
      return;
    }
    _flushOutput(deviceId, sessionId);
    _appendOutputNow(deviceId, sessionId, [(chunk, type)]);
  }

  void _flushOutput(String deviceId, String sessionId) {
    _outputTimers.remove(sessionId);
    final pending = _pendingOutput.remove(sessionId);
    if (pending != null && pending.isNotEmpty) {
      _appendOutputNow(deviceId, sessionId, pending);
    }
  }

  /// 一批输出只复制和发布一次会话状态，限制高频 stdout 引起的 rebuild。
  void _appendOutputNow(
    String deviceId,
    String sessionId,
    List<(String, TerminalLineType)> chunks,
  ) {
    final sessions = state.getSessions(deviceId);
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index == -1) return;

    final session = sessions[index];
    final currentLines = List<TerminalLine>.from(session.lines);

    for (final (chunk, type) in chunks) {
      final cleanChunk = chunk.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
      if (cleanChunk.isEmpty) continue;
      final newParts = cleanChunk.split(RegExp(r'\r\n|\n|\r'));
      if (currentLines.isEmpty) {
        currentLines.add(TerminalLine(text: '', type: type));
      }
      final lastLine = currentLines.last;
      if (lastLine.type == type || lastLine.text.isEmpty) {
        currentLines[currentLines.length - 1] = TerminalLine(
          text: _boundedLine(lastLine.text + newParts[0]),
          type: type,
        );
      } else {
        currentLines.add(
          TerminalLine(text: _boundedLine(newParts[0]), type: type),
        );
      }
      for (int i = 1; i < newParts.length; i++) {
        currentLines.add(
          TerminalLine(text: _boundedLine(newParts[i]), type: type),
        );
      }
    }
    if (currentLines.length > _maxOutputLines) {
      currentLines.removeRange(0, currentLines.length - _maxOutputLines);
    }

    _updateSession(deviceId, sessionId, (s) => s.copyWith(lines: currentLines));
  }

  String _boundedLine(String text) => text.length <= _maxLineLength
      ? text
      : text.substring(text.length - _maxLineLength);

  /// 追加应用内状态文案，交给 UI 根据当前语言渲染。
  void _appendLocalizedOutput(
    String deviceId,
    String sessionId,
    String key,
    TerminalLineType type, {
    Map<String, String> args = const {},
  }) {
    _flushOutput(deviceId, sessionId);
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

  /// 清空终端输出缓冲区及尚未发布的输出。
  void clearBuffer(String deviceId, String sessionId) {
    _outputTimers.remove(sessionId)?.cancel();
    _pendingOutput.remove(sessionId);
    _updateSession(deviceId, sessionId, (s) => s.copyWith(lines: []));
  }

  /// 历史命令上下翻页。
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
}
