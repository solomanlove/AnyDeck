import 'package:flutter/material.dart';

/// 应用列表 A-Z 字母索引侧边栏。
///
/// 允许用户点击或滑过特定字母，快速触发滚动至对应首字母的应用处。
class AppsAlphabetSidebar extends StatelessWidget {
  const AppsAlphabetSidebar({
    super.key,
    required this.availableLetters,
    required this.onLetterSelected,
  });

  /// 当前列表中实际存在的字母集合（比如 ['A', 'B', 'C', ...]）
  final Set<String> availableLetters;

  /// 点击或拖动选定字母时的回调
  final ValueChanged<String> onLetterSelected;

  static const List<String> _letters = [
    '#',
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: 22,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(11),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _letters.map((letter) {
            final isAvailable = availableLetters.contains(letter);
            return InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: isAvailable ? () => onLetterSelected(letter) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5, horizontal: 2),
                child: Text(
                  letter,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: isAvailable ? FontWeight.bold : FontWeight.normal,
                    color: isAvailable
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
