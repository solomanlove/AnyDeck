/// 编译期功能开关；不含 Share Core 的入口在所有窗口中使用同一常量。
abstract final class AnyDeckBuildFeatures {
  /// 默认保留完整功能，独立 Debug 入口显式传入 false。
  static const shareCore = bool.fromEnvironment(
    'ANYDECK_ENABLE_SHARE_CORE',
    defaultValue: true,
  );
}
