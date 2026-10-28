import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/nearby_share/share_transfer_history.dart';
import '../../../core/nearby_share/share_transfer_record.dart';
import 'harmony_share_record_tile.dart';

/// history 提供持久化分页；onOpen/onFolder/onRetry 交由上层执行路径操作或重试确认。
/// legacyPaths 仅兼容旧路径缓存，不补造方向和时间；删除按钮只删除记录。
/// 通过 showDialog(builder: (_) => HarmonyShareHistoryDialog(...)) 打开。
class HarmonyShareHistoryDialog extends StatefulWidget {
  const HarmonyShareHistoryDialog({
    super.key,
    required this.history,
    required this.onOpen,
    required this.onFolder,
    required this.onRetry,
    this.legacyPaths = const [],
  });
  final ShareTransferHistory history;
  final List<String> legacyPaths;
  final Future<void> Function(ShareTransferRecord) onOpen;
  final Future<void> Function(ShareTransferRecord) onFolder;
  final Future<void> Function(ShareTransferRecord) onRetry;
  @override
  State<HarmonyShareHistoryDialog> createState() =>
      _HarmonyShareHistoryDialogState();
}

class _HarmonyShareHistoryDialogState extends State<HarmonyShareHistoryDialog> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<ShareTransferRecord> _records = [];
  ShareTransferDirection? _direction;
  bool _loading = false;
  bool _more = true;
  bool _changed = false;
  bool _failed = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    widget.history.addListener(_historyChanged);
    unawaited(_load());
  }

  void _historyChanged() {
    if (mounted && !_changed) setState(() => _changed = true);
  }

  @override
  void dispose() {
    widget.history.removeListener(_historyChanged);
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more && _loading) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final rows = await widget.history.query(
        direction: _direction,
        search: _search.text.trim(),
        before: more && _records.isNotEmpty ? _records.last : null,
      );
      if (!mounted || revision != _revision) return;
      setState(() {
        _records = more ? [..._records, ...rows] : rows;
        _more = rows.length == 100;
        _changed = false;
      });
    } catch (_) {
      if (mounted && revision == _revision) setState(() => _failed = true);
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  Future<void> _remove(ShareTransferRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.t('harmonyShareRemoveRecord')),
        content: Text(context.l10n.t('harmonyShareRemoveRecordHint')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.t('shareTestCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.t('harmonyShareRemoveRecord')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.history.remove(record);
      await _load();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        Expanded(child: Text(context.l10n.t('harmonyShareHistory'))),
        IconButton(
          tooltip: context.l10n.t('harmonyShareHistoryRefresh'),
          onPressed: _loading ? null : () => _load(),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    content: SizedBox(
      width: 760,
      height: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final direction in [null, ...ShareTransferDirection.values])
                ChoiceChip(
                  label: Text(
                    context.l10n.t(
                      direction == null
                          ? 'harmonyShareAll'
                          : 'harmonyShareDirection_${direction.name}',
                    ),
                  ),
                  selected: _direction == direction,
                  onSelected: (_) {
                    setState(() => _direction = direction);
                    _load();
                  },
                ),
            ],
          ),
          if (widget.legacyPaths.isNotEmpty)
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  scrollable: true,
                  title: Text(context.l10n.t('harmonyShareLegacyPaths')),
                  content: SelectableText(widget.legacyPaths.join('\n\n')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.l10n.t('harmonyShareGotIt')),
                    ),
                  ],
                ),
              ),
              child: Text(context.l10n.t('harmonyShareLegacyPaths')),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: context.l10n.t('harmonyShareHistorySearch'),
            ),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 300),
                () => _load(),
              );
            },
          ),
          if (_changed)
            TextButton(
              onPressed: _loading ? null : () => _load(),
              child: Text(context.l10n.t('harmonyShareHistoryUpdated')),
            ),
          if (_loading) const LinearProgressIndicator(),
          if (_failed && _records.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                context.l10n.t('harmonyShareHistoryError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _records.isEmpty && !_loading
                ? Center(
                    child: Text(
                      context.l10n.t(
                        _failed
                            ? 'harmonyShareHistoryError'
                            : 'harmonyShareNoRecent',
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _records.length + (_more ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _records.length) {
                        return TextButton(
                          onPressed: _loading ? null : () => _load(more: true),
                          child: Text(
                            context.l10n.t('harmonyShareHistoryMore'),
                          ),
                        );
                      }
                      final record = _records[index];
                      return HarmonyShareRecordTile(
                        record: record,
                        onDetails: () =>
                            showHarmonyShareRecordDetails(context, record, history: widget.history, onOpen: widget.onOpen, onFolder: widget.onFolder, onRetry: widget.onRetry),
                        onOpen: record.path == null || record.fileCount > 1
                            ? null
                            : () => widget.onOpen(record),
                        onFolder: record.path == null
                            ? null
                            : () => widget.onFolder(record),
                        onRetry: record.canRetry
                            ? () {
                                Navigator.pop(context);
                                widget.onRetry(record);
                              }
                            : null,
                        onRemove: record.terminal
                            ? () => _remove(record)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.t('harmonyShareGotIt')),
      ),
    ],
  );
}
