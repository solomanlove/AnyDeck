import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../process/tool_path_resolver.dart';
import 'harmony_terminal_command.dart';
import 'terminal_newline_normalizer.dart';
import 'terminal_session_models.dart';

export 'harmony_terminal_command.dart';
export 'terminal_session_models.dart';

/// 终端会话管理器 Notifier
class AdbTerminalNotifier extends Notifier<AdbTerminalState> {
  final Map<String, Future<void>> _harmonyCommandQueues = {};

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

  /// 启动 Android 交互式 shell 进程；鸿蒙不支持 stdio TTY，改为逐条执行命令。
  Future<Process> _startShellProcess(
    String deviceId, {
    required bool isHarmony,
  }) async {
    if (isHarmony) {
      throw UnsupportedError('HarmonyOS does not support stdio TTY');
    }
    final adbPath = resolveToolPath('adb');
    // stdin 是管道，必须强制申请 PTY，才能收到设备真实的提示符和输入回显。
    return Process.start(adbPath, ['-s', deviceId, 'shell', '-tt']);
  }

  /// 创建并启动一个新的终端会话
  Future<void> createSession(String deviceId, {bool isHarmony = false}) async {
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final currentSessions = state.getSessions(deviceId);

    final session = AdbTerminalSession(
      id: sessionId,
      deviceId: deviceId,
      lines: [],
      commandHistory: [],
      historyIndex: -1,
      isRunning: true,
      isHarmony: isHarmony,
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

    // HarmonyOS 的 `hdc shell` 不支持持续写入 stdin；会话只承载 UI 与历史记录，
    // 实际命令由 sendCommand 逐条启动 HDC 子进程执行。
    if (isHarmony) return;

    try {
      final process = await _startShellProcess(deviceId, isHarmony: isHarmony);

      _updateSession(deviceId, sessionId, (s) => s.copyWith(process: process));

      // 监听 stdout
      process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const TerminalNewlineNormalizer())
          .listen((data) {
            _appendOutput(deviceId, sessionId, data, TerminalLineType.stdout);
          });

      // 监听 stderr
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const TerminalNewlineNormalizer())
          .listen((data) {
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
          (s) => s.copyWith(isRunning: false, clearProcess: true),
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
        (s) => s.copyWith(isRunning: false, clearProcess: true),
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

  /// 发送命令；Android 写入 PTY stdin，HarmonyOS 逐条启动 HDC shell。
  void sendCommand(String deviceId, String sessionId, String command) {
    final sessions = state.getSessions(deviceId);
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index == -1) return;

    final session = sessions[index];
    if (!session.isRunning) {
      _appendLocalizedOutput(
        deviceId,
        sessionId,
        'terminalOfflineCannotSend',
        TerminalLineType.info,
      );
      return;
    }

    if (!session.isHarmony && session.process == null) {
      _appendLocalizedOutput(
        deviceId,
        sessionId,
        'terminalOfflineCannotSend',
        TerminalLineType.info,
      );
      return;
    }

    final newHistory = [...session.commandHistory, command];
    _updateSession(deviceId, sessionId, (s) {
      return s.copyWith(
        commandHistory: newHistory,
        historyIndex: newHistory.length,
      );
    });

    if (session.isHarmony) {
      _appendOutput(
        deviceId,
        sessionId,
        '\$ $command\n',
        TerminalLineType.input,
      );
      final previous = _harmonyCommandQueues[sessionId] ?? Future.value();
      late final Future<void> queued;
      queued = previous
          .then((_) => _runHarmonyCommand(deviceId, sessionId, command))
          .whenComplete(() {
            if (identical(_harmonyCommandQueues[sessionId], queued)) {
              _harmonyCommandQueues.remove(sessionId);
            }
          });
      _harmonyCommandQueues[sessionId] = queued;
      return;
    }

    session.process!.stdin.write('$command\n');

    // 输入及提示符由 PTY 回显，不能本地重复追加，也不能猜测 su 是否成功。
  }

  /// HarmonyOS 不支持交互式 stdin，单条命令使用独立 HDC shell 进程执行并回写输出。
  Future<void> _runHarmonyCommand(
    String deviceId,
    String sessionId,
    String command,
  ) async {
    final sessionExists = state
        .getSessions(deviceId)
        .any((session) => session.id == sessionId && session.isRunning);
    if (!sessionExists) return;

    try {
      final hdcPath = resolveToolPath('hdc');
      final process = await Process.start(
        hdcPath,
        harmonyShellArguments(deviceId, command),
      );
      _updateSession(deviceId, sessionId, (s) => s.copyWith(process: process));

      final stdoutDone = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const TerminalNewlineNormalizer())
          .forEach((data) {
            _appendOutput(deviceId, sessionId, data, TerminalLineType.stdout);
          });
      final stderrDone = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const TerminalNewlineNormalizer())
          .forEach((data) {
            _appendOutput(deviceId, sessionId, data, TerminalLineType.stderr);
          });

      await Future.wait([stdoutDone, stderrDone, process.exitCode]);
      _updateSession(
        deviceId,
        sessionId,
        (s) => s.copyWith(clearProcess: true),
      );
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
        (s) => s.copyWith(clearProcess: true),
      );
    }
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
      (s) => s.copyWith(lines: [], isRunning: true, clearProcess: true),
    );

    if (session.isHarmony) return;

    try {
      final process = await _startShellProcess(
        deviceId,
        isHarmony: session.isHarmony,
      );

      _updateSession(deviceId, sessionId, (s) => s.copyWith(process: process));

      process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const TerminalNewlineNormalizer())
          .listen((data) {
            _appendOutput(deviceId, sessionId, data, TerminalLineType.stdout);
          });

      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const TerminalNewlineNormalizer())
          .listen((data) {
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
          (s) => s.copyWith(isRunning: false, clearProcess: true),
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
        (s) => s.copyWith(isRunning: false, clearProcess: true),
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
