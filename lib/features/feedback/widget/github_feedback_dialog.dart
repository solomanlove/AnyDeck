import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/providers/app_providers.dart';
import '../model/github_feedback.dart';

/// 预览反馈模板并跳转 GitHub；无需设备连接，复用当前语言和主题。
///
/// 无参数，通过 showDialog 展示。失败时保留草稿和链接复制入口。
class GithubFeedbackDialog extends ConsumerStatefulWidget {
  const GithubFeedbackDialog({super.key});

  @override
  ConsumerState<GithubFeedbackDialog> createState() =>
      _GithubFeedbackDialogState();
}

class _GithubFeedbackDialogState extends ConsumerState<GithubFeedbackDialog> {
  FeedbackKind _kind = FeedbackKind.bug;
  bool _busy = false;
  String? _statusKey;
  bool _isError = false;
  Uri? _failedUri;

  Future<void> _open(Uri uri) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusKey = null;
      _failedUri = null;
    });
    final opened = await ref.read(hostPlatformServiceProvider).openWebUri(uri);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _isError = !opened;
      _statusKey = opened ? 'feedbackOpened' : 'feedbackOpenFailed';
      _failedUri = opened ? null : uri;
    });
  }

  Future<void> _copy(Uri uri) async {
    try {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      if (!mounted) return;
      setState(() {
        _isError = false;
        _statusKey = 'feedbackLinkCopied';
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
    final body = GithubFeedback.body(l10n, _kind, Platform.operatingSystem);
    final uri = GithubFeedback.newIssueUri(_kind, body);

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
                      selected: _kind == kind,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              _kind = kind;
                              _statusKey = null;
                              _failedUri = null;
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                l10n.t('feedbackPreview'),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(body, style: theme.textTheme.bodySmall),
              ),
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
          onPressed: _busy ? null : () => _copy(_failedUri ?? uri),
          child: Text(l10n.t('feedbackCopyLink')),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : () => _open(uri),
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
