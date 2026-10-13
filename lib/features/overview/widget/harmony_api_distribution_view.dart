import 'dart:io';
import 'package:flutter/material.dart';

import '../model/harmony_version_distribution_data.dart';
import 'harmony_distribution_details_pane.dart';

/// HarmonyOS 平台与 API 版本分布专属视图。
///
/// 独立于 Android 和 iOS 视图，展现双编号（版本号 / API 版本）生态、
/// 存量占比与累计覆盖率、DevEco 工程配置及 1.0 起历史技术底座变迁。
class HarmonyApiDistributionView extends StatefulWidget {
  /// 构造函数
  const HarmonyApiDistributionView({
    super.key,
    this.initialVersion,
  });

  /// 初始选中的版本（如 7.0.0, 6.1.1）
  final String? initialVersion;

  @override
  State<HarmonyApiDistributionView> createState() =>
      _HarmonyApiDistributionViewState();
}

class _HarmonyApiDistributionViewState
    extends State<HarmonyApiDistributionView> {
  late HarmonyDistributionItem _selectedItem;
  bool _isHistoryExpanded = false;

  @override
  void initState() {
    super.initState();
    _selectedItem = _findInitialItem(widget.initialVersion);
  }

  HarmonyDistributionItem _findInitialItem(String? version) {
    if (version != null && version.isNotEmpty) {
      for (final item in HarmonyVersionDistributionData.items) {
        if (item.version == version ||
            item.api == version ||
            item.apiNum.toString() == version) {
          return item;
        }
      }
    }
    return HarmonyVersionDistributionData.items.first;
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
        // 核心双栏内容区域（左列表，右详情）
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左侧版本与 API 分布栏
              SizedBox(
                width: 420,
                child: _buildLeftList(isDark),
              ),
              // 垂直分割线
              Container(width: 1, color: dividerColor),
              // 右侧特性与配置详情
              Expanded(
                child: HarmonyDistributionDetailsPane(
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

  /// 构建左侧双编号版本列表
  Widget _buildLeftList(bool isDark) {
    final headerTextColor = isDark
        ? Colors.white.withValues(alpha: 0.65)
        : const Color(0xFF57606A);

    return Column(
      children: [
        // 表头
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Text(
                  'HarmonyOS 版本（版本号 / API）',
                  style: TextStyle(
                    color: headerTextColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 80,
                child: Center(
                  child: Text(
                    'API 版本',
                    style: TextStyle(
                      color: headerTextColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Text(
                  '存量占比 / 累计覆盖',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: headerTextColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        // 列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            itemCount: HarmonyVersionDistributionData.items.length,
            itemBuilder: (context, index) {
              final item = HarmonyVersionDistributionData.items[index];
              final isSelected = item.version == _selectedItem.version;

              return _buildRowItem(item, isSelected, isDark);
            },
          ),
        ),
      ],
    );
  }

  /// 构建单行条目
  Widget _buildRowItem(
    HarmonyDistributionItem item,
    bool isSelected,
    bool isDark,
  ) {
    final isEol = item.muteFlag == 'EOL';
    final blkBg = isEol
        ? (isDark ? const Color(0xFF383B40) : const Color(0xFFE2E4E8))
        : const Color(0xFFE84335);
    final blkFg = isEol
        ? (isDark ? Colors.white70 : const Color(0xFF57606A))
        : Colors.white;

    final rowBg = isSelected
        ? (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFFE84335).withValues(alpha: 0.08))
        : Colors.transparent;

    return InkWell(
      onTap: () => setState(() => _selectedItem = item),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 52,
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: rowBg,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border.all(
                  color: const Color(0xFFE84335),
                  width: 1.5,
                )
              : null,
        ),
        child: Row(
          children: [
            // 左侧版本块
            Container(
              width: 140,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: blkBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.version,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: blkFg,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (item.muteFlag != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: item.muteFlag == 'NEW'
                                ? Colors.white
                                : Colors.black.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            item.muteFlag!,
                            style: TextStyle(
                              color: item.muteFlag == 'NEW'
                                  ? const Color(0xFFE84335)
                                  : blkFg,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    'API ${item.api}',
                    style: TextStyle(
                      color: blkFg.withValues(alpha: 0.8),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // 中间大号 API 级别
            SizedBox(
              width: 80,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${item.apiNum}',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF24292F),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'API 版本',
                    style: TextStyle(
                      color: isDark ? Colors.white38 : const Color(0xFF6E7781),
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            // 右侧占比与累计覆盖
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    item.share,
                    style: const TextStyle(
                      color: Color(0xFFE84335),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    '累计 ${item.cover}',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : const Color(0xFF57606A),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建底部历史版本折叠面板
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
                    color: const Color(0xFFE84335),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      '历史版本（HarmonyOS 1.0 起 · 5.0 起为纯自研原生鸿蒙，与 1.0–4.x 非同一技术栈）',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE84335),
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
                      1: FlexColumnWidth(1.5),
                      2: FlexColumnWidth(3),
                      3: FlexColumnWidth(3),
                      4: FlexColumnWidth(1.2),
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
                          _HistHeadCell('API 版本'),
                          _HistHeadCell('发布时间'),
                          _HistHeadCell('技术底座'),
                          _HistHeadCell('存量占比'),
                        ],
                      ),
                      ...HarmonyVersionDistributionData.historyItems.map(
                        (h) => TableRow(
                          children: [
                            _HistCell(h.version),
                            _HistCell(h.api),
                            _HistCell(h.releaseDate),
                            _HistCell(h.architecture),
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
