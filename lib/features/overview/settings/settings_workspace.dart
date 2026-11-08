import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import 'settings_item.dart';
import '../../../app/widget/app_navigation_item.dart';

/// 设置分类导航与全局搜索，不修改设置值。
///
/// items 提供目录和原有控件；cardBuilder 复用现有 Card 外观。
/// 可用宽度不足 900px 时改用分类下拉框，各分类保留独立滚动位置。
class SettingsWorkspace extends StatefulWidget {
  const SettingsWorkspace({
    super.key,
    required this.items,
    required this.cardBuilder,
  });

  final List<SettingsItem> items;
  final Widget Function(String title, List<Widget> children) cardBuilder;

  @override
  State<SettingsWorkspace> createState() => _SettingsWorkspaceState();
}

class _SettingsWorkspaceState extends State<SettingsWorkspace> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _anchors = <String, GlobalKey>{};
  final _offsets = <SettingsCategory, double>{};
  SettingsCategory _category = SettingsCategory.general;
  String _query = '';
  String? _highlighted;
  int _navigation = 0;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _rememberPosition() {
    if (_query.isEmpty && _scroll.hasClients) {
      _offsets[_category] = _scroll.offset;
    }
  }

  void _setQuery(String value) {
    _rememberPosition();
    _navigation++;
    setState(() => _query = value.trim());
    if (_query.isEmpty) _restorePosition();
  }

  void _restorePosition() {
    final navigation = ++_navigation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || navigation != _navigation || !_scroll.hasClients) return;
      _scroll.jumpTo(
        (_offsets[_category] ?? 0).clamp(0, _scroll.position.maxScrollExtent),
      );
    });
  }

  void _selectCategory(SettingsCategory category) {
    _rememberPosition();
    _search.clear();
    setState(() {
      _category = category;
      _query = '';
      _highlighted = null;
    });
    _restorePosition();
  }

  /// 先挂载目标分类，再定位设置行；异步回调受导航版本保护。
  void _openResult(SettingsItem item) {
    final label = item.resultLabel(_query);
    final navigation = ++_navigation;
    _search.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _category = item.category;
      _query = '';
      _highlighted = item.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || navigation != _navigation) return;
      final anchor = _anchors[item.id]?.currentContext;
      if (anchor == null) return;
      // 快捷键、通知等复合控件直接定位到命中的具体文案。
      BuildContext target = anchor;
      void visit(Element element) {
        final widget = element.widget;
        if (widget is Text && widget.data == label) target = element;
        element.visitChildren(visit);
      }

      (anchor as Element).visitChildren(visit);
      Scrollable.ensureVisible(target, alignment: 0.15);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 900;
        return Padding(
          padding: EdgeInsets.all(narrow ? 16 : 24),
          child: Column(
            children: [
              TextField(
                key: const ValueKey('settings-search'),
                controller: _search,
                onChanged: _setQuery,
                decoration: InputDecoration(
                  hintText: l10n.t('settingsSearchHint'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: l10n.t('settingsClearSearch'),
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            _setQuery('');
                          },
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (narrow) ...[
                DropdownButtonFormField<SettingsCategory>(
                  key: ValueKey('settings-category-${_category.name}'),
                  initialValue: _category,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.t('settingsCategory'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final category in SettingsCategory.values)
                      DropdownMenuItem(
                        value: category,
                        child: Text(l10n.t(category.labelKey)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) _selectCategory(value);
                  },
                ),
                const SizedBox(height: 16),
              ],
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!narrow) ...[
                      SizedBox(
                        key: const ValueKey('settings-category-navigation'),
                        width: 160,
                        child: ListView(
                          children: [
                            for (final category in SettingsCategory.values)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Tooltip(
                                  message: l10n.t(category.labelKey),
                                  child: AppNavigationItem(
                                    key: ValueKey(
                                      'settings-nav-${category.name}',
                                    ),
                                    selected:
                                        _category == category && _query.isEmpty,
                                    icon: category.icon,
                                    label: l10n.t(category.labelKey),
                                    onTap: () => _selectCategory(category),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                    ],
                    Expanded(
                      child: _query.isEmpty
                          ? _buildCategory(context)
                          : _buildResults(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategory(BuildContext context) {
    final items = widget.items.where((item) => item.category == _category);
    final sections = <String, List<Widget>>{};
    for (final item in items) {
      final child = Container(
        key: _anchors.putIfAbsent(item.id, GlobalKey.new),
        decoration: BoxDecoration(
          border: _highlighted == item.id
              ? Border(
                  left: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                )
              : null,
        ),
        child: item.child,
      );
      (sections[item.section] ??= []).add(child);
    }
    return SingleChildScrollView(
      key: ValueKey('settings-content-${_category.name}'),
      controller: _scroll,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final section in sections.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child:
                      items.any(
                        (item) =>
                            item.section == section.key && item.standalone,
                      )
                      ? Column(children: section.value)
                      : widget.cardBuilder(section.key, section.value),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    final l10n = context.l10n;
    final results = widget.items
        .where((item) => item.matches(_query, l10n.t(item.category.labelKey)))
        .toList();
    if (results.isEmpty) {
      return Center(child: Text(l10n.t('settingsSearchEmpty')));
    }
    return ListView.builder(
      key: const ValueKey('settings-search-results'),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final item = results[index];
        return ListTile(
          key: ValueKey('settings-result-${item.id}'),
          leading: Icon(item.category.icon),
          title: Text(item.resultLabel(_query)),
          subtitle: Text(
            '${l10n.t(item.category.labelKey)} · ${item.section}'
            '${item.description.isEmpty ? '' : '\n${item.description}'}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openResult(item),
        );
      },
    );
  }
}
