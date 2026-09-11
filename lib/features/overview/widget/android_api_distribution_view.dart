import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../app/l10n/app_localizations.dart';
import '../model/android_version_distribution_data.dart';
import 'android_distribution_details_pane.dart';

/// Android 平台与 API 版本分布主视图面板，高度还原 Android Studio 官方设计。
/// 全面自适应主窗口的明暗主题与中英文语言环境。
class AndroidApiDistributionView extends StatefulWidget {
  const AndroidApiDistributionView({
    super.key,
    this.initialVersion,
    this.isStandaloneWindow = false,
    this.onClose,
  });

  /// 初始默认选中的版本（如连接设备的版本），若未提供则默认选中最新版 (Android 16)
  final String? initialVersion;

  /// 是否作为独立 macOS 窗口运行
  final bool isStandaloneWindow;

  /// 关闭回调
  final VoidCallback? onClose;

  @override
  State<AndroidApiDistributionView> createState() =>
      _AndroidApiDistributionViewState();
}

class _AndroidApiDistributionViewState
    extends State<AndroidApiDistributionView> {
  late AndroidDistributionItem _selectedItem;

  @override
  void initState() {
    super.initState();
    _selectedItem = AndroidVersionDistributionData.findItem(
      widget.initialVersion ?? '16',
    );
  }

  void _handleClose() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (widget.isStandaloneWindow) {
      windowManager.close();
    } else {
      Navigator.of(context).maybePop();
    }
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
    final langCode = Localizations.localeOf(context).languageCode;

    final windowBg = isDark ? const Color(0xFF232528) : const Color(0xFFF6F8FA);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    return Container(
      decoration: BoxDecoration(
        color: windowBg,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Column(
        children: [
          // 1. macOS 风格标题栏（可拖拽，随明暗主题自适应）
          _buildMacTitleBar(isDark),
          // 2. 核心内容区域（左侧分布柱形图，右侧特性详情）
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 左侧版本与 API 分布栏
                SizedBox(
                  width: 410,
                  child: _buildLeftDistributionPane(isDark),
                ),
                // 垂直分割线
                Container(
                  width: 1,
                  color: dividerColor,
                ),
                // 右侧版本特性列表与详情
                Expanded(
                  child: _buildRightDetailsPane(),
                ),
              ],
            ),
          ),
          // 3. 底部状态栏与 Close 按钮
          _buildBottomBar(isDark, langCode),
        ],
      ),
    );
  }

  /// 构建 macOS 风格的窗体标题栏
  Widget _buildMacTitleBar(bool isDark) {
    final titleBarBg = isDark ? const Color(0xFF2D3035) : const Color(0xFFEBECEF);
    final titleBarBorder = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.08);
    final titleTextColor = isDark
        ? Colors.white.withValues(alpha: 0.85)
        : const Color(0xFF1F2328);

    final titleBarContent = Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: titleBarBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        border: Border(
          bottom: BorderSide(
            color: titleBarBorder,
            width: 1,
          ),
        ),
      ),
      child: Center(
        child: Text(
          context.l10n.t('androidApiDistribution'),
          style: TextStyle(
            color: titleTextColor,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );

    return widget.isStandaloneWindow
        ? DragToMoveArea(child: titleBarContent)
        : titleBarContent;
  }

  /// 构建左侧版本与 API 分布列表
  Widget _buildLeftDistributionPane(bool isDark) {
    final reversedItems =
        AndroidVersionDistributionData.items.reversed.toList();
    final headerTextColor = isDark
        ? Colors.white.withValues(alpha: 0.65)
        : const Color(0xFF57606A);
    final scaleLineColor = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.12);
    final percentTextColor = isDark
        ? Colors.white.withValues(alpha: 0.85)
        : const Color(0xFF24292F);

    return Column(
      children: [
        // 表头（跟随语言切换）
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 150,
                child: Text(
                  context.l10n.t('androidPlatformVersionHeader'),
                  style: TextStyle(
                    color: headerTextColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
              SizedBox(
                width: 100,
                child: Center(
                  child: Text(
                    context.l10n.t('apiLevelHeader'),
                    style: TextStyle(
                      color: headerTextColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  context.l10n.t('cumulativeDistributionHeader'),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: headerTextColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        // 分布图表条块列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
            itemCount: reversedItems.length,
            itemBuilder: (context, index) {
              final item = reversedItems[index];
              final isSelected = item.apiLevel == _selectedItem.apiLevel;
              final height = _computeRowHeight(item.apiLevel);

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedItem = item;
                  });
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    height: height,
                    margin: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 彩色条形块
                        Expanded(
                          flex: 7,
                          child: Container(
                            decoration: BoxDecoration(
                              color: item.barColor,
                              border: isSelected
                                  ? Border.all(
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF0969DA),
                                      width: isDark ? 2 : 2.5,
                                    )
                                  : null,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                // 版本号与代号 (如 16 B, 15 V, 5.1 Lollipop)
                                Text(
                                  '${item.platformVersion}   ${item.codename}',
                                  style: TextStyle(
                                    color: const Color(0xFF1E2022),
                                    fontSize: height < 24 ? 11 : 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                // 居中/右侧大号 API Level 字符
                                Positioned(
                                  right: 20,
                                  child: Text(
                                    '${item.apiLevel}',
                                    style: TextStyle(
                                      color: const Color(0xFF1E2022)
                                          .withValues(alpha: height < 30 ? 0.4 : 0.22),
                                      fontSize: height < 30
                                          ? 14
                                          : (height * 0.72).clamp(18.0, 48.0),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // 累计占比刻度线与百分比
                        Expanded(
                          flex: 3,
                          child: Stack(
                            children: [
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  height: 1,
                                  color: scaleLineColor,
                                ),
                              ),
                              Positioned(
                                top: 3,
                                right: 6,
                                child: Text(
                                  item.cumulativeDistributionText,
                                  style: TextStyle(
                                    color: percentTextColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 依据 API 级别动态分配行高，还原市场占有率比例
  double _computeRowHeight(int apiLevel) {
    if (apiLevel >= 35) return 64.0;
    if (apiLevel == 34) return 58.0;
    if (apiLevel == 33) return 50.0;
    if (apiLevel == 31) return 46.0;
    if (apiLevel == 30) return 48.0;
    if (apiLevel == 29) return 38.0;
    if (apiLevel == 28) return 28.0;
    return 20.0;
  }

  /// 构建右侧选定版本的特性详情
  Widget _buildRightDetailsPane() {
    return AndroidDistributionDetailsPane(
      item: _selectedItem,
      onOpenUrl: _openUrl,
    );
  }

  /// 底部更新时间与 Close 按钮
  Widget _buildBottomBar(bool isDark, String langCode) {
    final bottomBarBg =
        isDark ? const Color(0xFF232528) : const Color(0xFFF6F8FA);
    final borderTopColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.08);
    final dateColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFF6E7781);

    final btnBg = isDark ? const Color(0xFF383B40) : const Color(0xFFE6E8EB);
    final btnFg = isDark ? Colors.white : const Color(0xFF1F2328);
    final btnBorder = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFD0D7DE);

    final dateText =
        '${context.l10n.t('lastUpdatedPrefix')}${AndroidVersionDistributionData.localizedLastUpdatedDate(langCode)}';

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: bottomBarBg,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
        border: Border(
          top: BorderSide(
            color: borderTopColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            dateText,
            style: TextStyle(
              color: dateColor,
              fontSize: 12,
            ),
          ),
          ElevatedButton(
            onPressed: _handleClose,
            style: ElevatedButton.styleFrom(
              backgroundColor: btnBg,
              foregroundColor: btnFg,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(
                  color: btnBorder,
                ),
              ),
            ),
            child: Text(
              context.l10n.t('close'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
