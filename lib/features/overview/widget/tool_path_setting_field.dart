import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/process/tool_path_settings.dart';
import 'tool_path_availability_badge.dart';

/// 核心 CLI 路径编辑器，负责输入和文件选择，不承担持久化与命令执行。
///
/// [toolName] 用于稳定的控件标识；[value] 是已保存的自定义路径，空值表示自动查找。
/// [resolvedPath] 展示当前实际使用的路径；[onChanged] 保存或以空值恢复默认。
/// [onOpen] 打开当前工具目录，参数为 true 时打开终端；[pickFile] 可替换文件选择器。
class ToolPathSettingField extends StatefulWidget {
  const ToolPathSettingField({
    super.key,
    required this.toolName,
    required this.value,
    required this.resolvedPath,
    required this.onChanged,
    required this.onOpen,
    this.pickFile,
  });

  final String toolName;
  final String value;
  final String resolvedPath;
  final Future<void> Function(String path) onChanged;
  final Future<void> Function(bool terminal) onOpen;
  final Future<String?> Function()? pickFile;

  @override
  State<ToolPathSettingField> createState() => _ToolPathSettingFieldState();
}

class _ToolPathSettingFieldState extends State<ToolPathSettingField> {
  late final TextEditingController _controller;
  bool _busy = false;
  int _availabilityRevision = 0;
  String? _errorKey;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant ToolPathSettingField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _controller.text = widget.value;
      _errorKey = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 对文件选择、保存和系统目录操作共用防重门控，并保留失败时的草稿。
  Future<void> _perform(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      await operation();
    } on ToolPathValidationException catch (error) {
      if (mounted) setState(() => _errorKey = error.code);
    } catch (_) {
      if (mounted) setState(() => _errorKey = 'toolPathSaveFailed');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _availabilityRevision++;
        });
      }
    }
  }

  Future<void> _save(String value) => _perform(() async {
    final path = value.trim();
    await widget.onChanged(path);
    if (mounted) _controller.text = path;
  });

  Future<void> _choose() => _perform(() async {
    final path = widget.pickFile != null
        ? await widget.pickFile!()
        : (await openFile())?.path;
    if (path != null && mounted) _controller.text = path;
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.t(
                  widget.value.isEmpty ? 'toolPathAutomatic' : 'toolPathCustom',
                ),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              ToolPathAvailabilityBadge(
                toolName: widget.toolName,
                resolvedPath: widget.resolvedPath,
                revision: _availabilityRevision,
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            l10n.t('toolPathCurrent').replaceAll('{path}', widget.resolvedPath),
            key: ValueKey('tool-current-${widget.toolName}'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            key: ValueKey('tool-path-${widget.toolName}'),
            controller: _controller,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: _save,
            decoration: InputDecoration(
              labelText: l10n.t('toolPathExecutable'),
              hintText: l10n.t('toolPathPlaceholder'),
              errorText: _errorKey == null ? null : l10n.t(_errorKey!),
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: ValueKey('tool-choose-${widget.toolName}'),
                onPressed: _busy ? null : _choose,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: Text(l10n.t('toolPathChoose')),
              ),
              FilledButton(
                key: ValueKey('tool-save-${widget.toolName}'),
                onPressed: _busy ? null : () => _save(_controller.text),
                child: Text(l10n.t('save')),
              ),
              TextButton(
                key: ValueKey('tool-reset-${widget.toolName}'),
                onPressed: _busy || widget.value.isEmpty
                    ? null
                    : () => _save(''),
                child: Text(l10n.t('toolPathReset')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                key: ValueKey('tool-open-directory-${widget.toolName}'),
                onPressed: _busy
                    ? null
                    : () => _perform(() => widget.onOpen(false)),
                icon: const Icon(Icons.folder_outlined, size: 18),
                label: Text(l10n.t('toolPathOpenDirectory')),
              ),
              TextButton.icon(
                key: ValueKey('tool-open-terminal-${widget.toolName}'),
                onPressed: _busy
                    ? null
                    : () => _perform(() => widget.onOpen(true)),
                icon: const Icon(Icons.terminal_outlined, size: 18),
                label: Text(l10n.t('toolPathOpenTerminal')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.t('toolPathEffect'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
