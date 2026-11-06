import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../core/adb/discovered_device.dart';
import '../../core/ios/ios_mirror_service.dart';
import '../../core/logcat/bounded_log_buffer.dart';
import '../../core/logcat/logcat_line_reader.dart';

/// 显示 go-ios syslog 持续流，并限制内存和刷新频率。
class IosSyslogTab extends ConsumerStatefulWidget {
  const IosSyslogTab({
    super.key,
    required this.device,
    this.isVisible = true,
  });

  /// 独立使用可保留 true；IndexedStack 中须传入实际 Tab 可见性以暂停后台工作。
  final bool isVisible;

  final DiscoveredDevice device;

  /// 解析 go-ios syslog --parse 格式的 JSON 字符串，转为清晰易读的日志行
  static String formatSyslogLine(String rawLine) {
    if (!rawLine.startsWith('{') || !rawLine.endsWith('}')) {
      return rawLine;
    }
    try {
      final decoded = jsonDecode(rawLine);
      if (decoded is Map<String, dynamic>) {
        final timestamp = decoded['timestamp'] as String?;
        final process = decoded['process'] as String?;
        final pid = decoded['pid']?.toString();
        final level = decoded['level'] as String?;
        final message = decoded['message'] as String?;

        if (message != null || process != null) {
          final buffer = StringBuffer();
          if (timestamp != null && timestamp.isNotEmpty) {
            final time = timestamp.contains('T')
                ? timestamp.split('T').last
                : timestamp;
            buffer.write('[$time] ');
          }
          if (level != null && level.isNotEmpty) {
            buffer.write('[$level] ');
          }
          if (process != null && process.isNotEmpty) {
            buffer.write('$process${pid != null ? '($pid)' : ''}: ');
          }
          buffer.write(message ?? '');
          return buffer.toString();
        }

        final msg = decoded['msg'] as String?;
        if (msg != null) {
          final lvl = decoded['level'] ?? 'INFO';
          return '[$lvl] $msg';
        }
      }
    } catch (_) {}
    return rawLine;
  }

  @override
  ConsumerState<IosSyslogTab> createState() => _IosSyslogTabState();
}

class _IosSyslogTabState extends ConsumerState<IosSyslogTab> {
  final _scrollController = ScrollController();
  final _lines = BoundedLogBuffer();
  final _pending = BoundedLogBuffer(maxLines: 1000, maxCharacters: 1024 * 1024);
  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Timer? _flushTimer;
  bool _running = false;
  bool _starting = false;
  bool _stopping = false;
  bool _autoScroll = true;
  String _filterKeyword = '';
  int _sessionRevision = 0;
  bool _resumeCapture = false;
  Future<void>? _stopTask;

  @override
  void didUpdateWidget(covariant IosSyslogTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id) {
      _lines.clear();
      unawaited(_stop());
    } else if (oldWidget.isVisible != widget.isVisible ||
        oldWidget.device.isOnline != widget.device.isOnline) {
      unawaited(_syncVisibility());
    }
  }

  /// 自动暂停保留用户的开始意图；手动停止后再次切页不会重启。
  Future<void> _syncVisibility() async {
    if (!widget.isVisible || !widget.device.isOnline) {
      await _stop(preserveIntent: true);
      return;
    }
    await _stopTask;
    if (mounted && widget.isVisible && _resumeCapture) await _start();
  }

  @override
  void dispose() {
    _sessionRevision++;
    _running = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    _pending.clear();
    _stdoutSubscription?.cancel();
    _stderrSubscription?.cancel();
    // 退出页面时立即彻底强杀 go-ios syslog 子进程，防止后台孤儿进程常驻
    try {
      _process?.kill(ProcessSignal.sigkill);
    } catch (_) {}
    _process = null;
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_running || _starting || _stopping || !widget.isVisible ||
        !widget.device.isOnline) {
      return;
    }
    final revision = ++_sessionRevision;
    _resumeCapture = true;
    setState(() => _starting = true);
    try {
      final process = await ref
          .read(iosCommandServiceProvider)
          .startSyslog(widget.device.id);

      // 若启动期间页面已被销毁或已触发停止，立即强杀该进程
      if (!mounted || revision != _sessionRevision || !widget.isVisible) {
        try {
          process.kill(ProcessSignal.sigkill);
        } catch (_) {}
        return;
      }

      _process = process;
      _running = true;
      _starting = false;

      _stdoutSubscription = readBoundedLogcatLines(
        process.stdout.transform(const Utf8Decoder(allowMalformed: true)),
      ).listen(_append);
      _stderrSubscription = readBoundedLogcatLines(
        process.stderr.transform(const Utf8Decoder(allowMalformed: true)),
      ).listen((line) => _append('[stderr] $line'));

      process.exitCode.whenComplete(() {
        if (mounted && identical(_process, process)) {
          setState(() {
            _running = false;
            _resumeCapture = false;
            _starting = false;
            _stopping = false;
            _process = null;
          });
        }
      });
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted || revision != _sessionRevision) return;
      _resumeCapture = false;
      if (mounted) {
        setState(() {
          _running = false;
          _starting = false;
          _stopping = false;
          _process = null;
        });
      }
      _append(error.toString());
      _scheduleFlush();
    }
  }

  void _append(String line) {
    if (!_running) return;
    _pending.add(IosSyslogTab.formatSyslogLine(line));
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(milliseconds: 100), () {
      _flushTimer = null;
      if (!mounted || _pending.isEmpty) return;
      setState(() {
        _lines.addAll(_pending.lines);
        _pending.clear();
      });
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    });
  }

  Future<void> _stop({bool updateUi = true, bool preserveIntent = false}) {
    if (!preserveIntent) _resumeCapture = false;
    return _stopTask ??= _stopCore(updateUi).whenComplete(() => _stopTask = null);
  }

  Future<void> _stopCore(bool updateUi) async {
    _sessionRevision++;
    if (!_running && !_starting && _process == null) return;

    // 1. 立即更新状态并清空暂存，阻断后续日志进入
    _running = false;
    _starting = false;
    _stopping = true;
    _pending.clear();
    _flushTimer?.cancel();
    _flushTimer = null;
    if (updateUi && mounted) setState(() {});

    // 2. 剥离实例引用并立即发送 SIGTERM
    final process = _process;
    _process = null;
    final stdoutSub = _stdoutSubscription;
    _stdoutSubscription = null;
    final stderrSub = _stderrSubscription;
    _stderrSubscription = null;

    try {
      process?.kill(ProcessSignal.sigterm);
    } catch (_) {}

    // 3. 异步取消流监听
    try {
      await stdoutSub?.cancel();
    } catch (_) {}
    try {
      await stderrSub?.cancel();
    } catch (_) {}

    // 4. 等待进程退出，若 300ms 未响应则以 SIGKILL 强杀兜底
    if (process != null) {
      try {
        await process.exitCode.timeout(
          const Duration(milliseconds: 300),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      } catch (_) {
        try {
          process.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
    }

    _stopping = false;
    if (updateUi && mounted) setState(() {});
  }

  List<String> get _displayLines {
    if (_filterKeyword.trim().isEmpty) return _lines.lines.toList(growable: false);
    final kw = _filterKeyword.toLowerCase();
    return _lines.lines.where((line) => line.toLowerCase().contains(kw)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final displayLines = _displayLines;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                context.l10n.t('iosSyslog'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              SizedBox(
                width: 180,
                height: 32,
                child: TextField(
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 16),
                    hintText: context.l10n.t('searchLogsHint'),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (val) => setState(() => _filterKeyword = val),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: _autoScroll ? '暂停自动滚动' : '开启自动滚动',
                icon: Icon(
                  _autoScroll
                      ? Icons.vertical_align_bottom
                      : Icons.vertical_align_bottom_outlined,
                  color: _autoScroll
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                onPressed: () => setState(() => _autoScroll = !_autoScroll),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: (_starting || _stopping)
                    ? null
                    : (_running ? () => _stop() : _start),
                icon: (_starting || _stopping)
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_running ? Icons.stop : Icons.play_arrow),
                label: Text(
                  _stopping
                      ? '停止中...'
                      : (_starting
                          ? '启动中...'
                          : context.l10n.t(
                              _running ? 'iosStopLog' : 'iosStartLog',
                            )),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => setState(_lines.clear),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text(context.l10n.t('clear')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: displayLines.isEmpty
                  ? Center(child: Text(context.l10n.t('iosNoLogs')))
                  : SelectionArea(
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: displayLines.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                          child: Text(
                            displayLines[index],
                            style: const TextStyle(
                              fontFamily: 'Menlo',
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
