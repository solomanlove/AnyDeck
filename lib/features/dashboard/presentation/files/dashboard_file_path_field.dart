part of '../dashboard_screen.dart';

/// 文件管理地址栏输入框，独立管理光标位置和外部路径同步。
class _PathTextField extends StatelessWidget {
  const _PathTextField({required this.initialPath, required this.onSubmitted});

  final String initialPath;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey(initialPath),
      autofocus: true,
      initialValue: initialPath,
      decoration: const InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: 8),
      ),
      style: Theme.of(context).textTheme.bodyMedium,
      onFieldSubmitted: onSubmitted,
    );
  }
}
