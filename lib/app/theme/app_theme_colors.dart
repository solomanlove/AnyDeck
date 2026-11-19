import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_theme_sizes.dart';

/// AnyDeck 业务组件使用的语义颜色，补充 Material [ColorScheme] 未覆盖的场景。
@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  const AppThemeColors({
    required this.toolbarForeground,
    required this.subtleBorder,
    required this.strongBorder,
    required this.success,
    required this.warning,
    required this.glassSurface,
    required this.panelSurface,
    required this.sunkenSurface,
    required this.subtleSurface,
    required this.hoverSurface,
    required this.subtleDivider,
    required this.softDivider,
    required this.mutedForeground,
    required this.faintForeground,
  });

  final Color toolbarForeground;
  final Color subtleBorder;
  final Color strongBorder;
  final Color success;
  final Color warning;
  final Color glassSurface;
  final Color panelSurface;
  final Color sunkenSurface;
  final Color subtleSurface;
  final Color hoverSurface;
  final Color subtleDivider;
  final Color softDivider;
  final Color mutedForeground;
  final Color faintForeground;

  static const light = AppThemeColors(
    toolbarForeground: Colors.black87,
    subtleBorder: Color(0xffe2e8f0),
    strongBorder: Color(0xffcbd5e1),
    success: AppPalette.primary,
    warning: Colors.orange,
    glassSurface: Color(0x47ffffff),
    panelSurface: Colors.white,
    sunkenSurface: Color(0xfff7f8fb),
    subtleSurface: Color(0x05000000),
    hoverSurface: Color(0x0d000000),
    subtleDivider: Colors.black12,
    softDivider: Colors.black12,
    mutedForeground: Colors.black54,
    faintForeground: Colors.black38,
  );

  static const dark = AppThemeColors(
    toolbarForeground: Colors.white70,
    subtleBorder: Color(0xff334155),
    strongBorder: Color(0xff475569),
    success: AppPalette.primary,
    warning: Colors.orange,
    glassSurface: Color(0x2e000000),
    panelSurface: Color(0xff1e293b),
    sunkenSurface: Color(0xff0f172a),
    subtleSurface: Color(0x0affffff),
    hoverSurface: Color(0x14ffffff),
    subtleDivider: Colors.white12,
    softDivider: Colors.white10,
    mutedForeground: Colors.white60,
    faintForeground: Colors.white38,
  );

  @override
  AppThemeColors copyWith({
    Color? toolbarForeground,
    Color? subtleBorder,
    Color? strongBorder,
    Color? success,
    Color? warning,
    Color? glassSurface,
    Color? panelSurface,
    Color? sunkenSurface,
    Color? subtleSurface,
    Color? hoverSurface,
    Color? subtleDivider,
    Color? softDivider,
    Color? mutedForeground,
    Color? faintForeground,
  }) {
    return AppThemeColors(
      toolbarForeground: toolbarForeground ?? this.toolbarForeground,
      subtleBorder: subtleBorder ?? this.subtleBorder,
      strongBorder: strongBorder ?? this.strongBorder,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      glassSurface: glassSurface ?? this.glassSurface,
      panelSurface: panelSurface ?? this.panelSurface,
      sunkenSurface: sunkenSurface ?? this.sunkenSurface,
      subtleSurface: subtleSurface ?? this.subtleSurface,
      hoverSurface: hoverSurface ?? this.hoverSurface,
      subtleDivider: subtleDivider ?? this.subtleDivider,
      softDivider: softDivider ?? this.softDivider,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      faintForeground: faintForeground ?? this.faintForeground,
    );
  }

  @override
  AppThemeColors lerp(covariant AppThemeColors? other, double t) {
    if (other == null) return this;
    return AppThemeColors(
      toolbarForeground: Color.lerp(
        toolbarForeground,
        other.toolbarForeground,
        t,
      )!,
      subtleBorder: Color.lerp(subtleBorder, other.subtleBorder, t)!,
      strongBorder: Color.lerp(strongBorder, other.strongBorder, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      glassSurface: Color.lerp(glassSurface, other.glassSurface, t)!,
      panelSurface: Color.lerp(panelSurface, other.panelSurface, t)!,
      sunkenSurface: Color.lerp(sunkenSurface, other.sunkenSurface, t)!,
      subtleSurface: Color.lerp(subtleSurface, other.subtleSurface, t)!,
      hoverSurface: Color.lerp(hoverSurface, other.hoverSurface, t)!,
      subtleDivider: Color.lerp(subtleDivider, other.subtleDivider, t)!,
      softDivider: Color.lerp(softDivider, other.softDivider, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      faintForeground: Color.lerp(faintForeground, other.faintForeground, t)!,
    );
  }
}

/// 提供与 [ThemeData.colorScheme] 一致的业务语义色访问入口。
extension AppThemeDataColors on ThemeData {
  /// 公共组件独立放入标准 MaterialApp 时也提供安全的明暗语义色。
  AppThemeColors get appColors =>
      extension<AppThemeColors>() ??
      (brightness == Brightness.dark ? AppThemeColors.dark : AppThemeColors.light);

  /// 工具环境缺失提示使用黄色标识，分别保证明暗背景上的文字对比度。
  Color get environmentWarningForeground => brightness == Brightness.dark
      ? const Color(0xffffdf80)
      : const Color(0xff705500);

  Color get environmentWarningBackground => brightness == Brightness.dark
      ? const Color(0xff40350e)
      : const Color(0xfffff2bf);

  /// 主窗口导航使用不透明中性底色，与右侧内容形成稳定分区。
  Color get navigationSurface => brightness == Brightness.dark
      ? const Color(0xff282a31) : const Color(0xffeceef2);

  /// 设备筛选、视图切换及批量选择共用中性灰色，不依赖品牌主色。
  Color get deviceSelectionBackground => appColors.subtleBorder;
  Color get deviceSelectionBorder => appColors.strongBorder;

  /// 批量勾选的选中与未选中边框均保持灰色，避免继承品牌色边框。
  WidgetStateBorderSide get deviceSelectionCheckboxSide =>
      WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.selected)
              ? colorScheme.onSurface
              : colorScheme.outline,
          width: AppThemeSizes.strongBorderWidth,
        ),
      );

  /// 主侧栏与设置分类共用的选中背景，明暗差异统一收口。
  Color get navigationSelectedBackground => colorScheme.primary.withValues(
    alpha: brightness == Brightness.dark ? 0.18 : 0.09,
  );

  /// 导航普通态与禁用态沿用主侧栏配色，避免分类栏使用另一套文字色。
  Color get navigationForeground => brightness == Brightness.dark
      ? const Color(0xffeceff1) : const Color(0xff455a64);
  Color get navigationDisabledForeground => brightness == Brightness.dark
      ? const Color(0xff546e7a) : const Color(0xff8b9a9e);
}
