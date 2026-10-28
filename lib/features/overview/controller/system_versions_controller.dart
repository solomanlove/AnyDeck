import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/platform_distribution_type.dart';

/// 系统版本页的平台选择独立于设备，切换主窗口页面后仍保留。
final systemVersionsPlatformProvider =
    NotifierProvider<
      SystemVersionsPlatformController,
      PlatformDistributionType
    >(SystemVersionsPlatformController.new);

class SystemVersionsPlatformController
    extends Notifier<PlatformDistributionType> {
  @override
  PlatformDistributionType build() => PlatformDistributionType.android;

  void select(PlatformDistributionType platform) => state = platform;
}
