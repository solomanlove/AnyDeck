part of '../dashboard_screen.dart';

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged, required this.hint});

  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(CupertinoIcons.search, size: 14),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        style: const TextStyle(fontSize: 12),
        onChanged: onChanged,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, required this.textColor});

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ExportedBadge extends StatelessWidget {
  const _ExportedBadge({required this.exported});
  final bool exported;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: exported ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        exported ? 'Exported' : 'Private',
        style: TextStyle(
          color: exported ? Colors.green.shade800 : Colors.grey.shade600,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _FallbackIconLarge extends StatelessWidget {
  const _FallbackIconLarge({required this.package, required this.theme});

  final AdbPackage package;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final colorScheme = theme.colorScheme;
    final icon = package.flutter
        ? CupertinoIcons.square_grid_2x2
        : package.system
            ? CupertinoIcons.settings
            : CupertinoIcons.device_phone_portrait;

    return Container(
      color: package.system
          ? colorScheme.surfaceContainerHighest
          : colorScheme.primaryContainer,
      child: Icon(
        icon,
        size: 36,
        color: package.system
            ? colorScheme.onSurfaceVariant
            : colorScheme.onPrimaryContainer,
      ),
    );
  }
}
