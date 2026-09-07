import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../core/adb/adb_device.dart';
import '../../core/ios/ios_mirror_service.dart';

/// 显示 go-ios syslog 持续流，并限制内存和刷新频率。
class IosSyslogTab extends ConsumerStatefulWidget {
  const IosSyslogTab({super.key, required this.device});

  final AdbDevice device;

  @override
  ConsumerState<IosSyslogTab> createState() => _IosSyslogTabState();
}

class _IosSyslogTabState extends ConsumerState<IosSyslogTab> {
  static const _maxLines = 3000;
  final _scrollController = ScrollController();
  final _lines = <String>[];
  final _pending = <String>[];
  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Timer? _flushTimer;
  bool _running = false;

  @override
  void dispose() {
    _stop(updateUi: false);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_running) return;
    try {
      final process = await ref
          .read(iosCommandServiceProvider)
          .startSyslog(widget.device.id);
      _process = process;
      _stdoutSubscription = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_append);
      _stderrSubscription = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) => _append('[stderr] $line'));
      process.exitCode.whenComplete(() {
        if (mounted && identical(_process, process)) {
          setState(() {
            _running = false;
            _process = null;
          });
        }
      });
      if (mounted) setState(() => _running = true);
    } catch (error) {
      _append(error.toString());
      _scheduleFlush();
    }
  }

  void _append(String line) {
    _pending.add(line);
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(milliseconds: 100), () {
      _flushTimer = null;
      if (!mounted || _pending.isEmpty) return;
      setState(() {
        _lines.addAll(_pending);
        _pending.clear();
        if (_lines.length > _maxLines) {
          _lines.removeRange(0, _lines.length - _maxLines);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    });
  }

  Future<void> _stop({bool updateUi = true}) async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    _process?.kill();
    _process = null;
    if (updateUi && mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
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
              FilledButton.icon(
                onPressed: _running ? () => _stop() : _start,
                icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                label: Text(
                  context.l10n.t(_running ? 'iosStopLog' : 'iosStartLog'),
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
              child: _lines.isEmpty
                  ? Center(child: Text(context.l10n.t('iosNoLogs')))
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _lines.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        child: SelectableText(
                          _lines[index],
                          style: const TextStyle(
                            fontFamily: 'Menlo',
                            fontSize: 11,
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
