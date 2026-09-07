import 'package:flutter/material.dart';

import '../../app/l10n/app_localizations.dart';

/// iOS 工具页统一的命令输出区域。
class IosCommandOutput extends StatelessWidget {
  const IosCommandOutput({super.key, required this.output});

  final String output;

  static const int _maxVisibleCharacters = 200000;

  @override
  Widget build(BuildContext context) {
    final trimmed = output.trim();
    final visibleOutput = trimmed.length > _maxVisibleCharacters
        ? trimmed.substring(trimmed.length - _maxVisibleCharacters)
        : trimmed;
    final value = visibleOutput.isEmpty
        ? context.l10n.t('iosNoOutput')
        : visibleOutput;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        value,
        style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
      ),
    );
  }
}

/// iOS 工具页统一的标题、说明和滚动布局。
class IosToolScaffold extends StatelessWidget {
  const IosToolScaffold({
    super.key,
    required this.title,
    required this.child,
    this.description,
  });

  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: SingleChildScrollView(
        primary: true,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (description != null) ...[
              const SizedBox(height: 6),
              Text(
                description!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
