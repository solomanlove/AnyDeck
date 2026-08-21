part of '../dashboard_screen.dart';

/// 根据当前远程路径构建可点击的面包屑导航。
List<Widget> _buildFileBreadcrumbs(
  BuildContext context,
  WidgetRef ref,
  String path,
) {
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  final list = <Widget>[];

  list.add(
    TextButton(
      onPressed: () {
        ref.read(fileNavigationProvider.notifier).navigateTo('/');
      },
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        context.l10n.t('storage'),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
  );

  var currentAccPath = '/';
  for (final segment in segments) {
    list.add(
      Text(
        ' > ',
        style: TextStyle(
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          fontSize: 12,
        ),
      ),
    );
    currentAccPath += '$segment/';
    final segmentPath = currentAccPath;
    list.add(
      TextButton(
        onPressed: () {
          ref.read(fileNavigationProvider.notifier).navigateTo(segmentPath);
        },
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          segment,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  return list;
}
