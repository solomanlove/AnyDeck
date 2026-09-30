import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_icon.dart';
import '../../../core/device_info/brand_logo_helper.dart';
import '../../../core/providers/modules/device_overview_providers.dart';
import '../../../core/providers/modules/registered_device_model.dart';

/// 设备品牌 Logo 与在线/离线状态指示头像组件。
///
/// 用途：
/// 1. 根据设备型号、自定义别名、品牌厂商或系统类型（Android/iOS/HarmonyOS）自适应匹配对应 Logo；
/// 2. 在线时以全彩饱满呈现，离线/未连接时应用灰度脱色滤镜和透明度，让状态一目了然；
/// 3. 在 Logo 右下角集成小圆点徽标（Badge），绿色代表在线，橙色代表未授权，灰色代表离线；
/// 4. 提供鼠标悬停 Tooltip，完整说明设备身份与当前连接状态。
///
/// 参数：
/// - [device]：要渲染的设备注册模型，包含在线状态、系统类型、型号等；
/// - [size]：头像尺寸正方形宽高，默认 38.0。
class DeviceStatusAvatar extends ConsumerWidget {
  const DeviceStatusAvatar({
    super.key,
    required this.device,
    this.size = 38.0,
  });

  /// 设备数据模型
  final RegisteredDevice device;

  /// 头像正方形边长尺寸
  final double size;

  /// 标准 ITU-R BT.709 灰阶加权滤镜矩阵，用于将彩色图片转换为纯灰度图像
  static const ColorFilter _greyscaleFilter = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0,      0,      0,      1, 0,
  ]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = device.isOnline;
    final isUnauthorized = device.status == 'unauthorized';

    // 1. 解析对应的品牌或系统 Logo 资源路径
    final logoAsset = _resolveLogoAsset(ref);

    // 2. 根据设备状态确定右下角徽标颜色与提示文字
    final Color statusDotColor;
    final String statusText;
    if (isOnline) {
      statusDotColor = const Color(0xFF10B981); // 在线：亮绿色
      statusText = context.l10n.t('deviceOnline');
    } else if (isUnauthorized) {
      statusDotColor = const Color(0xFFF59E0B); // 未授权：琥珀橙色
      statusText = context.l10n.t('deviceUnauthorized');
    } else {
      statusDotColor = const Color(0xFF94A3B8); // 离线：灰蓝色
      statusText = context.l10n.t('deviceOffline');
    }

    // 3. 构建 Logo 图像，并在离线或脱机状态下应用灰阶滤镜与透明度
    Widget logoWidget = Image.asset(
      logoAsset,
      fit: BoxFit.contain,
      width: size * 0.75,
      height: size * 0.75,
    );

    if (!isOnline) {
      logoWidget = ColorFiltered(
        colorFilter: _greyscaleFilter,
        child: Opacity(
          opacity: 0.45,
          child: logoWidget,
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avatarBg = isOnline
        ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF))
        : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9));

    final avatarBorder = isOnline
        ? (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))
        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1).withValues(alpha: 0.4));

    final dotSize = (size * 0.26).clamp(8.0, 10.0);

    return Tooltip(
      message: '${device.displayName} ($statusText)',
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Logo 容器背景与边框
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: avatarBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: avatarBorder, width: 1),
            ),
            alignment: Alignment.center,
            child: logoWidget,
          ),
          // 右下角在线/离线状态指示小圆点
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: statusDotColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 依据优先级综合推导设备的品牌 Logo 资源
  String _resolveLogoAsset(WidgetRef ref) {
    // 优先：系统级判断（iOS、HarmonyOS）
    if (device.isIos) {
      return AppIcons.apple;
    }
    if (device.isHarmony) {
      return AppIcons.huawei;
    }

    // 次优：从设备概览信息中获取精准识别的品牌厂商
    final overviewAsync = ref.watch(deviceOverviewProvider(device.id));
    if (overviewAsync.hasValue) {
      final overview = overviewAsync.value!;
      final asset = BrandLogoHelper.getBrandLogoAsset(
        overview.brand,
        manufacturer: overview.manufacturer,
      );
      if (asset != null) return asset;
    }

    // 再次：从自定义别名（如 "Redmi K40", "纯血鸿蒙"）中推导
    final nameAsset = BrandLogoHelper.getBrandLogoAsset(
      device.customName ?? '',
      manufacturer: device.model,
    );
    if (nameAsset != null) return nameAsset;

    // 再次：从硬件型号或产品代号推导
    final modelAsset = BrandLogoHelper.getBrandLogoAsset(
      device.model ?? '',
      manufacturer: device.product,
    );
    if (modelAsset != null) return modelAsset;

    // 默认兜底：通用 Android 图标
    return AppIcons.androidDefaultAppIcon;
  }
}
