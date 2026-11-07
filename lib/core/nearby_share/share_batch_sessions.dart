import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'share_batch_contract.dart';
import 'share_core_contract.dart';
import 'share_core_sessions.dart';
import 'share_file_progress.dart';

/// 一次原生发送批次；进度严格匹配已确认总量，成功终态优先于迟到取消。
class ShareBatchTransfer {
  ShareBatchTransfer(this._process, this.request, {String? coreExecutable})
      : _coreExecutable = coreExecutable {
    _result = _run();
    unawaited(_result.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }
  final Process _process;
  final String? _coreExecutable;
  final ShareBatchRequest request;
  final _progress = StreamController<ShareCoreProgress>.broadcast();
  late final Future<Map<String, dynamic>> _result;
  bool _cancelled = false;
  bool _timedOut = false;
  Stream<ShareCoreProgress> get progress => _progress.stream;
  Future<Map<String, dynamic>> get result => _result;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    unawaited(stopShareCoreProcess(_process, coreExecutable: _coreExecutable));
  }

  Future<Map<String, dynamic>> _run() async {
    Map<String, dynamic>? terminal;
    Object? failure;
    var previous = 0;
    final files = ShareFileProgressLedger(count: request.files.length,
      bytes: request.bytes, direction: 'send', sizes: request.files.map((file) => file.bytes).toList());
    final errors = _process.stderr.listen((_) {});
    final timer = Timer(
      ShareCoreContract.transferTimeout + const Duration(seconds: 10),
      () {
        _timedOut = true;
        unawaited(stopShareCoreProcess(_process, coreExecutable: _coreExecutable));
      },
    );
    try {
      await for (final line
          in _process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        final event = decodeShareCoreEvent(line);
        if (terminal != null) {
          throw const FormatException('Data after batch terminal');
        }
        if (event['event'] == 'progress') {
          final progress = ShareCoreProgress.parse(
            event,
            maxTotalBytes: ShareBatchContract.maxBytes,
          );
          if (progress.direction != 'send' ||
              progress.totalBytes != request.bytes ||
              progress.bytes < previous) {
            throw const FormatException('Invalid batch progress');
          }
          previous = progress.bytes;
          _progress.add(progress);
        } else if (event['event'] == 'file_progress') {
          _progress.add(files.accept(event));
        } else if (event['event'] == 'batch_sent') {
          if (event['file_count'] is! int ||
              event['file_count'] != request.files.length ||
              event['total_bytes'] is! int ||
              event['total_bytes'] != request.bytes ||
              event['remote_hash_verified'] != false) {
            throw const FormatException('Invalid batch completion');
          }
          terminal = event;
        } else if (event['event'] == 'error') {
          terminal = event;
        } else {
          throw const FormatException('Unexpected batch event');
        }
      }
    } catch (error) {
      failure = error;
      await stopShareCoreProcess(_process, coreExecutable: _coreExecutable);
    } finally {
      await errors.cancel();
      await _progress.close();
    }
    final exit = await _process.exitCode;
    timer.cancel();
    if (failure != null) throw failure;
    if (terminal?['event'] == 'batch_sent') return Map.unmodifiable(terminal!);
    if (_timedOut) throw TimeoutException('Batch transfer timed out');
    if (_cancelled) throw StateError('Batch transfer cancelled');
    throw StateError(
      'Share Core ${terminal?['code'] ?? exit}: ${terminal?['phase'] ?? ''} ${terminal?['reason'] ?? ''}',
    );
  }
}

/// 复用接收进程资源管理；仅在所有文件和摘要核对通过后发布本地整批完成事件。
class ShareBatchReceiveSession extends ShareCoreReceiveSession {
  ShareBatchReceiveSession(super.process, {required this.directory, super.coreExecutable});
  final String directory;
  ShareBatchReceived? _received;
  bool _decided = false;
  bool _accepted = false;
  bool _terminal = false;
  int _previous = 0;
  final _validatedDone = Completer<void>();
  bool _validating = false;
  ShareFileProgressLedger? _files;

  @override
  void decide(bool accept) {
    if (_received == null || _decided || _terminal) return;
    _decided = true;
    _accepted = accept;
    super.decide(accept);
  }

  @override
  Stream<Map<String, dynamic>> get events => _validate(super.events);

  @override
  Future<void> stop() async {
    await super.stop();
    if (_validating) await _validatedDone.future.timeout(const Duration(seconds: 2), onTimeout: () {});
  }

  Stream<Map<String, dynamic>> _validate(
    Stream<Map<String, dynamic>> source,
  ) async* {
    _validating = true;
    try {
      await for (final event in source) {
        if (_terminal) {
          throw const FormatException('Data after receive terminal');
        }
        switch (event['event']) {
          case 'incoming_batch':
            final count = event['file_count'];
            final bytes = event['total_bytes'];
            final ip = event['ip'];
            if (_received != null ||
                count is! int ||
                bytes is! int ||
                ip is! String ||
                InternetAddress.tryParse(ip)?.type !=
                    InternetAddressType.IPv4) {
              throw const FormatException('Invalid incoming batch');
            }
            _received = ShareBatchReceived(
              count: count,
              bytes: bytes,
              directory: directory,
            );
            _files = ShareFileProgressLedger(count: count, bytes: bytes, direction: 'receive');
            yield event;
          case 'file_progress':
            if (!_accepted || _files == null) {
              throw const FormatException('Unaccepted file progress');
            }
            yield _files!.accept(event).toMap();
          case 'progress':
            final progress = ShareCoreProgress.parse(
              event,
              maxTotalBytes: ShareBatchContract.maxBytes,
            );
            if (!_accepted ||
                progress.direction != 'receive' ||
                progress.totalBytes != _received?.bytes ||
                progress.bytes < _previous) {
              throw const FormatException('Invalid receive progress');
            }
            _previous = progress.bytes;
            yield event;
          case 'batch_file_received':
            if (!_accepted) {
              throw const FormatException('Unaccepted batch data');
            }
            _received!.add(event);
            _files!.checkResult(event['index'] as int, event['bytes'] as int);
          case 'batch_received':
            if (!_accepted) {
              throw const FormatException('Unaccepted batch result');
            }
            final files = _received!.finish(event);
            _terminal = true;
            yield {...event, 'files': files};
          case 'error':
            _terminal = true;
            yield event;
          case 'network_warning':
            if (!_accepted || _received == null ||
                !const {'direct_network_restore_failed', 'direct_network_restore_pending'}
                    .contains(event['reason'])) {
              throw const FormatException('Invalid network warning');
            }
            yield event;
          case 'network_connecting':
          case 'network_restoring':
            if (!_accepted || _received == null) {
              throw const FormatException('Unaccepted network transition');
            }
            yield event;
          case 'discovery_ready':
          case 'device':
          case 'session_started':
          case 'transfer_started':
            yield event;
          default:
            throw const FormatException('Unexpected batch receive event');
        }
      }
      if (_received != null && !_terminal) {
        throw StateError('Incomplete batch receive');
      }
    } catch (_) {
      unawaited(stop());
      rethrow;
    } finally {
      if (!_validatedDone.isCompleted) _validatedDone.complete();
    }
  }
}
