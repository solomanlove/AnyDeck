import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/widget/dashboard_history_text_field.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/search/dashboard_search_history_controller.dart';

/// 文件 Tab 的历史筛选输入框，Android 与 Harmony 页面复用同一份查询和历史。
class FileHistoryFilterField extends ConsumerStatefulWidget {
  const FileHistoryFilterField({super.key});

  @override
  ConsumerState<FileHistoryFilterField> createState() =>
      _FileHistoryFilterFieldState();
}

class _FileHistoryFilterFieldState
    extends ConsumerState<FileHistoryFilterField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(fileFilterQueryProvider),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history =
        ref.watch(filesSearchHistoryProvider).value ?? const <String>[];
    final query = ref.watch(fileFilterQueryProvider);
    return SizedBox(
      width: 150,
      height: 38,
      child: DashboardHistoryTextField(
        controller: _controller,
        hintText: context.l10n.t('filter'),
        history: history,
        onChanged: (value) =>
            ref.read(fileFilterQueryProvider.notifier).setQuery(value),
        onSubmitted: (value) =>
            ref.read(filesSearchHistoryProvider.notifier).add(value),
        onSelected: (value) =>
            ref.read(filesSearchHistoryProvider.notifier).add(value),
        onHistoryRemoved: (value) =>
            ref.read(filesSearchHistoryProvider.notifier).remove(value),
        textStyle: Theme.of(context).textTheme.bodyMedium,
        hasQuery: query.isNotEmpty,
        onClear: () {
          _controller.clear();
          ref.read(fileFilterQueryProvider.notifier).setQuery('');
        },
      ),
    );
  }
}
