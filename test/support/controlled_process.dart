import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 可手动推进双流与退出的进程桩，不启动任何外部程序。
class ControlledProcess extends Fake implements Process {
  final output = StreamController<List<int>>();
  final errors = StreamController<List<int>>();
  final ended = Completer<int>();
  final signals = <ProcessSignal>[];

  @override
  Stream<List<int>> get stdout => output.stream;
  @override
  Stream<List<int>> get stderr => errors.stream;
  @override
  Future<int> get exitCode => ended.future;
  @override
  int get pid => 42;

  void finish([int code = 0]) {
    if (!ended.isCompleted) ended.complete(code);
    if (!output.isClosed) unawaited(output.close());
    if (!errors.isClosed) unawaited(errors.close());
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    finish(-1);
    return true;
  }
}
