import 'dart:io';
import 'package:flutter/material.dart';

import '../model/ios_version_distribution_data.dart';
import 'ios_distribution_details_pane.dart';
import 'ios_adoption_samples.dart';

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

  /// 按来源、采样日期及统计对象分组，避免不同分母共用比例轴。
  Widget _buildLeftTimelineList(bool isDark) => IosAdoptionSamples(
    selectedVersion: _selectedItem.version,
    onSelected: (item) => setState(() => _selectedItem = item),
  );

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
            SelectionArea(
              child: Container(
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
