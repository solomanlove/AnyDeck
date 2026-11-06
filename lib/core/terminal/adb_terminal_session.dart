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

part 'terminal_output_buffer.dart';

/// 终端会话管理器 Notifier
class AdbTerminalNotifier extends Notifier<AdbTerminalState>
    with TerminalOutputBuffer {
  int _nextSessionId = 0;
  final Map<String, Future<void>> _harmonyCommandQueues = {};
  final Set<String> _suspendedDevices = {};
  final Map<String, int> _sessionGenerations = {};

  @override
  AdbTerminalState build() {
    var latestState = const AdbTerminalState();
    listenSelf((_, next) => latestState = next);
    ref.onDispose(() {
      for (final timer in _outputTimers.values) {
        timer.cancel();
      }
      _outputTimers.clear();
      _pendingOutput.clear();
      _suspendedDevices.clear();
      _sessionGenerations.clear();
      // 销毁时停止所有设备的所有交互式进程
      for (final sessions in latestState.deviceSessions.values) {
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
    final sessionId = '${DateTime.now().microsecondsSinceEpoch}-${_nextSessionId++}';
    final generation = _bumpSessionGeneration(sessionId);
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

      if (!ref.mounted || _suspendedDevices.contains(deviceId) ||
          _sessionGenerations[sessionId] != generation ||
          !state.getSessions(deviceId).any(
        (s) => s.id == sessionId && s.isRunning,
      )) {
        process.kill();
        return;
      }

      _updateSession(deviceId, sessionId, (s) => s.copyWith(process: process));

      // 监听 stdout
      process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const TerminalNewlineNormalizer())
          .listen((data) {
            if (ref.mounted && _sessionGenerations[sessionId] == generation) {
              _appendOutput(deviceId, sessionId, data, TerminalLineType.stdout);
            }
          });

      // 监听 stderr
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const TerminalNewlineNormalizer())
          .listen((data) {
            if (ref.mounted && _sessionGenerations[sessionId] == generation) {
              _appendOutput(deviceId, sessionId, data, TerminalLineType.stderr);
            }
          });

      // 进程退出处理
      process.exitCode.then((code) {
        if (!ref.mounted) return;
        final current = state.getSessions(deviceId).where((s) => s.id == sessionId);
        if (current.isEmpty || !identical(current.first.process, process)) return;
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
      if (!ref.mounted || _sessionGenerations[sessionId] != generation) return;
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

    _sessionGenerations.remove(sessionId);
    _outputTimers.remove(sessionId)?.cancel();
    _pendingOutput.remove(sessionId);

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

  /// 离开终端页时停止该设备的交互进程，保留已有输出和命令历史。
  void suspendDevice(String deviceId) {
    _suspendedDevices.add(deviceId);
    for (final session in state.getSessions(deviceId)) {
      _bumpSessionGeneration(session.id);
      _outputTimers.remove(session.id)?.cancel();
      _pendingOutput.remove(session.id);
      session.process?.kill();
      if (session.process != null || (!session.isHarmony && session.isRunning)) {
        _updateSession(deviceId, session.id,
            (s) => s.copyWith(
              isRunning: s.isHarmony,
              clearProcess: true,
            ));
      }
    }
  }

  /// 回到终端页时恢复 Android 会话，原有终端输出保持可见。
  Future<void> resumeDevice(String deviceId) async {
    _suspendedDevices.remove(deviceId);
    for (final session in state.getSessions(deviceId)) {
      if (!session.isHarmony && !session.isRunning && session.process == null) {
        await restartSession(deviceId, session.id, clearOutput: false);
      }
    }
  }

  /// 发送命令；Android 写入 PTY stdin，HarmonyOS 逐条启动 HDC shell。
  void sendCommand(String deviceId, String sessionId, String command) {
    final sessions = state.getSessions(deviceId);
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index == -1) return;
    final session = sessions[index];
    if (!session.isRunning || (!session.isHarmony && session.process == null)) {
      _appendLocalizedOutput(
        deviceId,
        sessionId,
        'terminalOfflineCannotSend',
        TerminalLineType.info,
      );
      return;
    }
    // 空回车只换行：Android 交给 PTY 回显，鸿蒙在本地生成下一行提示符。
    if (command.isEmpty) {
      if (session.isHarmony) {
        _appendOutput(deviceId, sessionId, '\$ \n', TerminalLineType.input);
      } else {
        session.process!.stdin.write('\n');
      }
      return;
    }

    final historyCommand = command.length > TerminalOutputBuffer._maxLineLength
        ? command.substring(0, TerminalOutputBuffer._maxLineLength)
        : command;
    final history = [...session.commandHistory, historyCommand];
    final newHistory = history.length > TerminalOutputBuffer._maxHistoryCommands
        ? history.sublist(history.length - TerminalOutputBuffer._maxHistoryCommands)
        : history;
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
    if (_suspendedDevices.contains(deviceId)) return;
    final generation = _sessionGenerations[sessionId];
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
      if (!ref.mounted || _suspendedDevices.contains(deviceId) ||
          _sessionGenerations[sessionId] != generation) {
        process.kill();
        return;
      }
      _updateSession(deviceId, sessionId, (s) => s.copyWith(process: process));

      final stdoutDone = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const TerminalNewlineNormalizer())
          .forEach((data) {
            if (_sessionGenerations[sessionId] == generation && ref.mounted) {
              _appendOutput(deviceId, sessionId, data, TerminalLineType.stdout);
            }
          });
      final stderrDone = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const TerminalNewlineNormalizer())
          .forEach((data) {
            if (_sessionGenerations[sessionId] == generation && ref.mounted) {
              _appendOutput(deviceId, sessionId, data, TerminalLineType.stderr);
            }
          });

      await Future.wait([stdoutDone, stderrDone, process.exitCode]);
      if (!ref.mounted || _sessionGenerations[sessionId] != generation) return;
      _updateSession(
        deviceId,
        sessionId,
        (s) => s.copyWith(clearProcess: true),
      );
    } on Object catch (e) {
      if (!ref.mounted || _sessionGenerations[sessionId] != generation) return;
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
  Future<void> restartSession(String deviceId, String sessionId,
      {bool clearOutput = true}) async {
    final sessions = state.getSessions(deviceId);
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index == -1) return;

    final generation = _bumpSessionGeneration(sessionId);
    _outputTimers.remove(sessionId)?.cancel();
    _pendingOutput.remove(sessionId);

    final session = sessions[index];
    session.process?.kill();

    _updateSession(
      deviceId,
      sessionId,
      (s) => s.copyWith(
        lines: clearOutput ? [] : s.lines,
        isRunning: true,
        clearProcess: true,
      ),
    );

    if (session.isHarmony) return;

    try {
      final process = await _startShellProcess(
        deviceId,
        isHarmony: session.isHarmony,
      );

      if (!ref.mounted || _suspendedDevices.contains(deviceId) ||
          _sessionGenerations[sessionId] != generation ||
          !state.getSessions(deviceId).any(
        (s) => s.id == sessionId && s.isRunning,
      )) {
        process.kill();
        return;
      }

      _updateSession(deviceId, sessionId, (s) => s.copyWith(process: process));

      process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const TerminalNewlineNormalizer())
          .listen((data) {
            if (ref.mounted && _sessionGenerations[sessionId] == generation) {
              _appendOutput(deviceId, sessionId, data, TerminalLineType.stdout);
            }
          });

      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const TerminalNewlineNormalizer())
          .listen((data) {
            if (ref.mounted && _sessionGenerations[sessionId] == generation) {
              _appendOutput(deviceId, sessionId, data, TerminalLineType.stderr);
            }
          });

      process.exitCode.then((code) {
        if (!ref.mounted) return;
        final current = state.getSessions(deviceId).where((s) => s.id == sessionId);
        if (current.isEmpty || !identical(current.first.process, process)) return;
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
      if (!ref.mounted || _sessionGenerations[sessionId] != generation) return;
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

  int _bumpSessionGeneration(String sessionId) =>
      _sessionGenerations[sessionId] = (_sessionGenerations[sessionId] ?? 0) + 1;
}
