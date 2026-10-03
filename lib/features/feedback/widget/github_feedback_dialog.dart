import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/providers/app_providers.dart';
import '../controller/feedback_draft_controller.dart';
import '../model/github_feedback.dart';

/// 编辑含环境快照的反馈草稿并跳转 GitHub，复用当前语言和主题。
///
/// 无参数，通过 showDialog 展示。失败时保留草稿和链接复制入口。
class GithubFeedbackDialog extends ConsumerStatefulWidget {
  const GithubFeedbackDialog({super.key});

  @override
  ConsumerState<GithubFeedbackDialog> createState() =>
      _GithubFeedbackDialogState();
}

class _GithubFeedbackDialogState extends ConsumerState<GithubFeedbackDialog> {
  FeedbackDraftController? _draft;
  bool _busy = false;
  String? _statusKey;
  bool _isError = false;
  Uri? _failedUri;
  bool _titleError = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 只初始化一次，主题、语言和设备变化均不得覆盖正在编辑的正文。
    _draft ??= FeedbackDraftController(
      context.l10n,
      ref.read(feedbackEnvironmentProvider),
    )..addListener(_onDraftChanged);
  }

  void _onDraftChanged() => setState(() {
    _statusKey = null;
    _failedUri = null;
    _titleError = false;
  });

  @override
  void dispose() {
    _draft?.removeListener(_onDraftChanged);
    _draft?.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final draft = _draft!;
    if (!draft.hasTitle) {
      setState(() => _titleError = true);
      return;
    }
    await _open(
      draft.launchUri,
      bodyToCopy: draft.needsBodyCopy ? draft.body.text : null,
    );
  }

  Future<void> _open(Uri uri, {String? bodyToCopy}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusKey = null;
      _failedUri = null;
    });
    // 超长正文先完整复制；剪贴板失败时停止跳转，避免用户误以为正文已携带。
    if (bodyToCopy != null) {
      try {
        await Clipboard.setData(ClipboardData(text: bodyToCopy));
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _isError = true;
          _statusKey = 'feedbackCopyFailed';
        });
        return;
      }
      if (!mounted) return;
    }
    final opened = await ref.read(hostPlatformServiceProvider).openWebUri(uri);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _isError = !opened;
      _statusKey = opened
          ? bodyToCopy == null
                ? 'feedbackOpened'
                : 'feedbackBodyCopiedOpen'
          : 'feedbackOpenFailed';
      _failedUri = opened ? null : uri;
    });
  }

  Future<void> _copy() async {
    final draft = _draft!;
    final copyBody = draft.needsBodyCopy;
    try {
      await Clipboard.setData(
        ClipboardData(
          text: copyBody
              ? draft.body.text
              : (_failedUri ?? draft.fullUri).toString(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _isError = false;
        _statusKey = copyBody ? 'feedbackBodyCopied' : 'feedbackLinkCopied';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isError = true;
        _statusKey = 'feedbackCopyFailed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final draft = _draft!;

    return AlertDialog(
      title: Text(l10n.t('feedbackTitle')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.t('feedbackNotice')),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final kind in FeedbackKind.values)
                    ChoiceChip(
                      label: Text(
                        l10n.t(
                          kind == FeedbackKind.bug
                              ? 'feedbackBug'
                              : 'feedbackFeature',
                        ),
                      ),
                      selected: draft.kind == kind,
                      onSelected: _busy
                          ? null
                          : (_) {
                              FocusScope.of(context).unfocus();
                              draft.select(kind);
                            },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('feedbackTitleField'),
                controller: draft.title,
                readOnly: _busy,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: l10n.t('feedbackTitleLabel'),
                  hintText: l10n.t('feedbackTitleHint'),
                  border: const OutlineInputBorder(),
                  errorText: _titleError
                      ? l10n.t('feedbackTitleRequired')
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('feedbackBodyField'),
                controller: draft.body,
                readOnly: _busy,
                minLines: 10,
                maxLines: 16,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: l10n.t('feedbackBodyLabel'),
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                ),
                style: theme.textTheme.bodySmall,
              ),
              if (draft.needsBodyCopy) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.t('feedbackLongBody'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              SelectableText(
                GithubFeedback.issuesUri.toString(),
                style: theme.textTheme.bodySmall,
              ),
              TextButton.icon(
                onPressed: _busy ? null : () => _open(GithubFeedback.issuesUri),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(l10n.t('feedbackViewIssues')),
              ),
              if (_statusKey != null)
                Text(
                  l10n.t(_statusKey!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _isError
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.t('close')),
        ),
        TextButton(
          onPressed: _busy ? null : _copy,
          child: Text(
            l10n.t(
              draft.needsBodyCopy ? 'feedbackCopyBody' : 'feedbackCopyLink',
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.open_in_new, size: 16),
          label: Text(l10n.t('feedbackOpenGithub')),
        ),
      ],
    );
  }
}
