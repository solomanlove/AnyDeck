import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../process/tool_path_resolver.dart';
import 'logcat_state.dart';

class LogcatController extends Notifier<LogcatState> {
  Process? _process;
  StreamSubscription<String>? _subscription;
  StreamSubscription<String>? _errorSubscription;

  @override
  LogcatState build() {
    ref.onDispose(stop);
    return const LogcatState();
  }

  Future<void> start(String deviceId, {String level = '*:V'}) async {
    await stop();
    state = state.copyWith(lines: [], isRunning: true);
    try {
      _process = await Process.start(resolveToolPath('adb'), [
        '-s',
        deviceId,
        'logcat',
        level,
      ]);
      _subscription = _process!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_appendLine);
      _errorSubscription = _process!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) => _appendLine('[stderr] $line'));
      _process!.exitCode.whenComplete(() {
        if (_process != null) {
          state = state.copyWith(isRunning: false);
        }
      });
    } on Object catch (error) {
      state = state.copyWith(isRunning: false, error: error.toString());
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    await _errorSubscription?.cancel();
    _subscription = null;
    _errorSubscription = null;
    _process?.kill();
    _process = null;
    state = state.copyWith(isRunning: false);
  }

  void clear() {
    state = state.copyWith(lines: []);
  }

  void setFilter(String value) {
    state = state.copyWith(filter: value);
  }

  List<String> visibleLines() {
    final filter = state.filter.trim();
    if (filter.isEmpty) {
      return state.lines;
    }
    final lowerFilter = filter.toLowerCase();
    return state.lines
        .where((line) => line.toLowerCase().contains(lowerFilter))
        .toList(growable: false);
  }

  void _appendLine(String line) {
    final next = [...state.lines, line];
    if (next.length > 1000) {
      next.removeRange(0, next.length - 1000);
    }
    state = state.copyWith(lines: next);
  }
}
