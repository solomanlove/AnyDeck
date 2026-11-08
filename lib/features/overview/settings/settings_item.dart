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
    this.standalone = false,
  });

  final String id;
  final SettingsCategory category;
  final String section;
  final String title;
  final String description;
  final String keywords;
  final List<String> searchLabels;
  final bool standalone;
  final Widget child;

  /// 忽略大小写与多余空白，多词查询按 AND 匹配。
  bool matches(String query, String categoryLabel) {
    final text =
        '$title $section $description $keywords '
                '${searchLabels.join(' ')} $categoryLabel'
            .toLowerCase();
    return query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .every(text.contains);
  }

  /// 复合设置优先展示命中的动作名称，帮助用户确认搜索结果。
  String resultLabel(String query) => searchLabels.firstWhere(
    (label) => label.toLowerCase().contains(query.trim().toLowerCase()),
    orElse: () => title,
  );
}
