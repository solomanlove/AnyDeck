import 'package:flutter/material.dart';

/// 设置分类的稳定标识；与本地化名称及持久化设置键独立。
enum SettingsCategory {
  general('settingsGeneral', Icons.tune),
  mirroring('settingsMirroringRecording', Icons.screen_share_outlined),
  receivers('settingsReceiving', Icons.cast),
  shortcuts('keyboardShortcuts', Icons.keyboard_outlined),
  notifications('settingsNotifications', Icons.notifications_outlined),
  storage('settingsStorageCache', Icons.folder_outlined),
  about('aboutAndSupport', Icons.info_outline);

  const SettingsCategory(this.labelKey, this.icon);
  final String labelKey;
  final IconData icon;
}

/// 展示与检索元数据。child 复用既有控件，搜索不会执行设置操作。
///
/// id 必须唯一；section 决定同分类内的 Card 分组；description 和 keywords
/// 用于检索。searchLabels 用于复合控件内的动作定位，standalone 表示自带 Card。
class SettingsItem {
  const SettingsItem({
    required this.id,
    required this.category,
    required this.section,
    required this.title,
    required this.child,
    this.description = '',
    this.keywords = '',
    this.searchLabels = const [],
    this.searchAliases = const {},
    this.standalone = false,
  });

  final String id;
  final SettingsCategory category;
  final String section;
  final String title;
  final String description;
  final String keywords;
  final List<String> searchLabels;

  /// 检索别名到实际动作文案的映射，例如当前按键组合到快捷键行名称。
  final Map<String, String> searchAliases;
  final bool standalone;
  final Widget child;

  /// 忽略大小写与多余空白，多词查询按 AND 匹配。
  bool matches(String query, String categoryLabel) {
    final text =
        '$title $section $description $keywords '
                '${searchLabels.join(' ')} ${searchAliases.keys.join(' ')} $categoryLabel'
            .toLowerCase();
    return _matchesQuery(text, query);
  }

  static bool _matchesQuery(String text, String query) => query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .every(text.toLowerCase().contains);

  /// 复合设置优先展示命中的动作名称，帮助用户确认搜索结果。
  String resultLabel(String query) {
    for (final label in searchLabels) {
      if (_matchesQuery(label, query)) return label;
    }
    for (final alias in searchAliases.entries) {
      if (_matchesQuery(alias.key, query)) return alias.value;
    }
    return title;
  }
}
