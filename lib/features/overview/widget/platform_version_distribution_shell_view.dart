import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../app/l10n/app_localizations.dart';
import '../model/platform_distribution_type.dart';
import 'android_api_distribution_view.dart';
import 'harmony_api_distribution_view.dart';
import 'ios_version_distribution_view.dart';
import 'platform_version_switcher.dart';

/// 跨平台版本与生态分布外壳容器视图（对齐 HTML 原型整体设计）。
///
/// 顶部展示 macOS 风格标题栏与右上角平台切换器（.pswitch 样式）；
/// 中间根据平台切换展示相互独立的 Android、HarmonyOS、iOS 视图 Widget；
/// 底部展示本端数据快照时间戳、口径提示标签及关闭按钮。
///
/// **用法示例**：
/// ```dart
/// PlatformVersionDistributionShellView(
///   initialPlatform: PlatformDistributionType.android,
///   isStandaloneWindow: true,
/// )
/// ```
class PlatformVersionDistributionShellView extends StatefulWidget {
  /// 构造函数
  const PlatformVersionDistributionShellView({
    super.key,
    this.initialPlatform = PlatformDistributionType.android,
    this.initialVersion,
    this.isStandaloneWindow = false,
    this.onClose,
  });

  /// 初始选中的平台类型
  final PlatformDistributionType initialPlatform;

  /// 初始选中的版本标识
  final String? initialVersion;

  /// 是否作为独立 macOS 窗口运行
  final bool isStandaloneWindow;

  /// 关闭窗口或弹窗回调
  final VoidCallback? onClose;

  @override
  State<PlatformVersionDistributionShellView> createState() =>
      _PlatformVersionDistributionShellViewState();
}

class _PlatformVersionDistributionShellViewState
    extends State<PlatformVersionDistributionShellView> {
  late PlatformDistributionType _currentPlatform;

  @override
  void initState() {
    super.initState();
    _currentPlatform = widget.initialPlatform;
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final langCode = Localizations.localeOf(context).languageCode;

    final windowBg = isDark ? const Color(0xFF232528) : const Color(0xFFF6F8FA);

    return Container(
      decoration: BoxDecoration(
        color: windowBg,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Column(
        children: [
          // 1. macOS 风格标题栏与右上角平台切换器
          _buildMacTitleBar(isDark),
          // 2. 核心独立平台内容视图
          Expanded(
            child: _buildPlatformBody(),
          ),
          // 3. 底部状态栏与 Close 按钮
          _buildBottomBar(isDark, langCode),
        ],
      ),
    );
  }

  /// 构建 macOS 风格窗体标题栏（包含平台切换器）
  Widget _buildMacTitleBar(bool isDark) {
    final titleBarBg = isDark ? const Color(0xFF2D3035) : const Color(0xFFEBECEF);
    final titleBarBorder = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.08);
    final titleTextColor = isDark
        ? Colors.white.withValues(alpha: 0.85)
        : const Color(0xFF1F2328);

    // 标题文本随所选平台动态切换
    final title = context.l10n.t(_currentPlatform.titleL10nKey);

    final titleBarContent = Container(
      height: 42,
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
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 居中窗口标题
          Center(
            child: Text(
              title,
              style: TextStyle(
                color: titleTextColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          // 右上角平台切换器（原型 .pswitch 样式）
          Positioned(
            right: 0,
            child: PlatformVersionSwitcher(
              selectedPlatform: _currentPlatform,
              onPlatformChanged: (platform) {
                setState(() => _currentPlatform = platform);
              },
            ),
          ),
        ],
      ),
    );

    return widget.isStandaloneWindow
        ? DragToMoveArea(child: titleBarContent)
        : titleBarContent;
  }

  /// 依据所选平台渲染专属独立视图
  Widget _buildPlatformBody() {
    switch (_currentPlatform) {
      case PlatformDistributionType.android:
        return AndroidApiDistributionView(
          initialVersion: widget.initialVersion,
          isEmbedded: true,
        );
      case PlatformDistributionType.harmony:
        return HarmonyApiDistributionView(
          initialVersion: widget.initialVersion,
        );
      case PlatformDistributionType.ios:
        return IosVersionDistributionView(
          initialVersion: widget.initialVersion,
        );
    }
  }

  /// 底部数据更新时间、数据来源说明 Flag 与 Close 按钮
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

    final updatePrefix = context.l10n.t('lastUpdatedPrefix');
    final dateText = '$updatePrefix${_currentPlatform.lastUpdatedDate}';
    final flagNotice = _currentPlatform.localizedFlagNotice(langCode);

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
          // 左侧：更新时间与口径提示 Flag 胶囊
          Row(
            children: [
              Text(
                dateText,
                style: TextStyle(
                  color: dateColor,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFB06000).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  flagNotice,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFB06000),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          // 右侧：关闭按钮
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
