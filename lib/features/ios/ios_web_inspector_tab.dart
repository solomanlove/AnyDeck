import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/l10n/app_localizations.dart';
import 'ios_tool_widgets.dart';

/// 通过 Safari 官方 Develop 菜单选择已允许检查的 iOS 网页目标。
class IosWebInspectorTab extends StatefulWidget {
  const IosWebInspectorTab({super.key});

  @override
  State<IosWebInspectorTab> createState() => _IosWebInspectorTabState();
}

class _IosWebInspectorTabState extends State<IosWebInspectorTab> {
  bool _opening = false;
  String? _error;

  Future<void> _openSafari() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final result = await Process.run('open', [
        '-a',
        'Safari',
      ]).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) {
        throw ProcessException('open', ['-a', 'Safari'], '${result.stderr}');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IosToolScaffold(
      title: context.l10n.t('webpages'),
      description: context.l10n.t('iosWebInspectorDescription'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.t('iosWebInspectorSteps')),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: Platform.isMacOS && !_opening ? _openSafari : null,
            icon: const Icon(Icons.open_in_new),
            label: Text(context.l10n.t('iosOpenSafariInspector')),
          ),
          if (!Platform.isMacOS) ...[
            const SizedBox(height: 8),
            Text(context.l10n.t('iosWebInspectorMacOnly')),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
