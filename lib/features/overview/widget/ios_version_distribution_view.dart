import 'dart:io';
import 'package:flutter/material.dart';

import '../model/ios_version_distribution_data.dart';
import 'ios_distribution_details_pane.dart';

/// Apple iOS 版本采用率与工具链矩阵专属视图。
///
/// 独立于 Android 和 HarmonyOS 视图，展现时间轴轨道演进、
/// 官方采用率与第三方快照、Xcode/Swift 工具链对应矩阵以及 1.0 起历史技术档案。
class IosVersionDistributionView extends StatefulWidget {
  /// 构造函数
  const IosVersionDistributionView({
    super.key,
    this.initialVersion,
  });

  /// 初始选中的版本（如 27, 26, 18）
  final String? initialVersion;

  @override
  State<IosVersionDistributionView> createState() =>
      _IosVersionDistributionViewState();
}

class _IosVersionDistributionViewState
    extends State<IosVersionDistributionView> {
  late IosDistributionItem _selectedItem;
  bool _isHistoryExpanded = false;

  @override
  void initState() {
    super.initState();
    _selectedItem = _findInitialItem(widget.initialVersion);
  }

  IosDistributionItem _findInitialItem(String? version) {
    if (version != null && version.isNotEmpty) {
      for (final item in IosVersionDistributionData.items) {
        if (item.version == version || 'iOS ${item.version}' == version) {
          return item;
        }
      }
    }
    return IosVersionDistributionData.items.first;
  }

  Future<void> _openUrl(String url) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      }
    } catch (e) {
      debugPrint('Failed to open url $url: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    return Column(
      children: [
        // 核心双栏内容区域（左时间轴列表，右详情）
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左侧时间轴大版本列表
              SizedBox(
                width: 420,
                child: _buildLeftTimelineList(isDark),
              ),
              // 垂直分割线
              Container(width: 1, color: dividerColor),
              // 右侧矩阵与特性详情
              Expanded(
                child: IosDistributionDetailsPane(
                  item: _selectedItem,
                  onOpenUrl: _openUrl,
                ),
              ),
            ],
          ),
        ),
        // 底部历史版本折叠面板（1.0 起）
        _buildHistorySection(isDark),
      ],
    );
  }

  /// 构建左侧时间轴列表
  Widget _buildLeftTimelineList(bool isDark) {
    final headerTextColor = isDark
        ? Colors.white.withValues(alpha: 0.65)
        : const Color(0xFF57606A);

    return Column(
      children: [
        // 表头
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'iOS 大版本（采用率口径，非 API Level）',
                style: TextStyle(
                  color: headerTextColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '设备占比',
                style: TextStyle(
                  color: headerTextColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        // 时间轴列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: IosVersionDistributionData.items.length,
            itemBuilder: (context, index) {
              final item = IosVersionDistributionData.items[index];
              final isSelected = item.version == _selectedItem.version;
              final isLast =
                  index == IosVersionDistributionData.items.length - 1;

              return _buildTimelineItem(item, isSelected, isLast, isDark);
            },
          ),
        ),
      ],
    );
  }

  /// 构建单行时间轴条目
  Widget _buildTimelineItem(
    IosDistributionItem item,
    bool isSelected,
    bool isLast,
    bool isDark,
  ) {
    // 进度条百分比（以最高值 79% 为基准）
    final maxRatio = 79.0;
    final barFactor = (item.sharePercent / maxRatio).clamp(0.06, 1.0);

    final rowBg = isSelected
        ? (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFF0969DA).withValues(alpha: 0.08))
        : Colors.transparent;

    final dotColor = isSelected
        ? const Color(0xFF0969DA)
        : (isDark ? Colors.white38 : const Color(0xFF9AA5B1));

    return InkWell(
      onTap: () => setState(() => _selectedItem = item),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: rowBg,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(
                  color: const Color(0xFF0969DA),
                  width: 1.5,
                )
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧时间轴轨道（圆点与垂直连线）
            SizedBox(
              width: 20,
              child: Column(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 2)
                          : null,
                    ),
                  ),
                  if (!isLast)
                    Container(
                      width: 1.5,
                      height: 48,
                      margin: const EdgeInsets.only(top: 3),
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 中间大版本名、徽章与占比条
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'iOS ${item.version}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF1F2328),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildBadge(item.badgeType, item.badgeText),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.minor} · 发布 ${item.date} · 数据源 ${item.source}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark ? Colors.white60 : const Color(0xFF57606A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 设备占比柱形条
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Container(
                      height: 4,
                      width: double.infinity,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.08),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: barFactor,
                        child: Container(
                          color: const Color(0xFF0969DA),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 右侧百分比与“设备占比”小字
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.share,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0969DA),
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  '设备占比',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white38 : const Color(0xFF6E7781),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 状态徽标
  Widget _buildBadge(String type, String text) {
    Color bg;
    Color fg;
    if (type == 'current') {
      bg = const Color(0xFF0969DA).withValues(alpha: 0.12);
      fg = const Color(0xFF0969DA);
    } else if (type == 'previous') {
      bg = const Color(0xFF2EA44F).withValues(alpha: 0.12);
      fg = const Color(0xFF2EA44F);
    } else {
      bg = Colors.grey.withValues(alpha: 0.15);
      fg = const Color(0xFF57606A);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// 底部历史版本折叠面板
  Widget _buildHistorySection(bool isDark) {
    final borderTopColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderTopColor)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() => _isHistoryExpanded = !_isHistoryExpanded);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _isHistoryExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18,
                    color: const Color(0xFF0969DA),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      '历史版本（iOS 1.0 起 · 已 EOL，Apple 未公布各版本占比）',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0969DA),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isHistoryExpanded)
            Container(
              height: 125,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListView(
                children: [
                  Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FlexColumnWidth(2.5),
                      2: FlexColumnWidth(3),
                      3: FlexColumnWidth(2.5),
                      4: FlexColumnWidth(1.5),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.black.withValues(alpha: 0.04),
                        ),
                        children: const [
                          _HistHeadCell('版本'),
                          _HistHeadCell('发布时间'),
                          _HistHeadCell('Xcode'),
                          _HistHeadCell('Swift'),
                          _HistHeadCell('状态'),
                        ],
                      ),
                      ...IosVersionDistributionData.historyItems.map(
                        (h) => TableRow(
                          children: [
                            _HistCell('iOS ${h.version}'),
                            _HistCell(h.releaseDate),
                            _HistCell(h.xcode),
                            _HistCell(h.swift),
                            const _HistCell('已 EOL', isBadge: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HistHeadCell extends StatelessWidget {
  const _HistHeadCell(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6E7781),
        ),
      ),
    );
  }
}

class _HistCell extends StatelessWidget {
  const _HistCell(this.text, {this.isBadge = false});
  final String text;
  final bool isBadge;

  @override
  Widget build(BuildContext context) {
    if (isBadge) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9, color: Color(0xFF6E7781)),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10.5),
      ),
    );
  }
}
