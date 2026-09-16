import 'package:flutter/material.dart';

/// 投屏异常类型分类枚举
enum MirrorErrorType {
  /// 设备已离线或未找到（例如 USB 拔出、Wi-Fi 掉线、device not found、device offline）
  offline,

  /// 设备未授权 USB 调试
  unauthorized,

  /// 网络连接超时
  timeout,

  /// 连接被拒绝（调试端口未开或服务未就绪）
  connectionRefused,

  /// 一般性/未知启动失败
  general,
}

/// 投屏错误解析模型，用于将底层的原始异常（如 adb 报错）转化为用户友好的结构化数据。
class MirrorErrorInfo {
  const MirrorErrorInfo({
    required this.type,
    required this.titleKey,
    required this.descriptionKey,
    this.fallbackDescription,
    this.rawError,
  });

  /// 错误分类
  final MirrorErrorType type;

  /// 标题多语言 Key
  final String titleKey;

  /// 描述信息多语言 Key
  final String descriptionKey;

  /// 兜底非模板化描述（如一般性异常时的原始精简消息）
  final String? fallbackDescription;

  /// 原始异常详情（用于复制或展开排查）
  final String? rawError;

  /// 是否为离线或断开状态
  bool get isOffline => type == MirrorErrorType.offline;

  /// 对应场景推荐图标
  IconData get icon {
    switch (type) {
      case MirrorErrorType.offline:
        return Icons.phonelink_erase_rounded;
      case MirrorErrorType.unauthorized:
        return Icons.security_rounded;
      case MirrorErrorType.timeout:
        return Icons.timer_off_outlined;
      case MirrorErrorType.connectionRefused:
        return Icons.portable_wifi_off_rounded;
      case MirrorErrorType.general:
        return Icons.error_outline_rounded;
    }
  }

  /// 根据原始错误文本进行智能解析与归类
  factory MirrorErrorInfo.fromRawError(String? rawError) {
    if (rawError == null || rawError.trim().isEmpty) {
      return const MirrorErrorInfo(
        type: MirrorErrorType.general,
        titleKey: 'mirrorStartFailed',
        descriptionKey: 'mirrorStartFailed',
      );
    }

    final lower = rawError.toLowerCase();

    // 1. 设备未找到 / 离线 / 断开连接
    // 匹配如: device 'xxx' not found, device offline, failed to get feature set, closed 等
    if (lower.contains('not found') ||
        lower.contains('offline') ||
        lower.contains('failed to get feature set') ||
        lower.contains('no such device') ||
        lower.contains('device disconnected') ||
        lower.contains('closed')) {
      return MirrorErrorInfo(
        type: MirrorErrorType.offline,
        titleKey: 'deviceDisconnected',
        descriptionKey: 'deviceOfflineHint',
        rawError: rawError,
      );
    }

    // 2. 设备未授权
    if (lower.contains('unauthorized')) {
      return MirrorErrorInfo(
        type: MirrorErrorType.unauthorized,
        titleKey: 'mirrorStartFailed',
        descriptionKey: 'deviceUnauthorizedHint',
        rawError: rawError,
      );
    }

    // 3. 连接超时
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return MirrorErrorInfo(
        type: MirrorErrorType.timeout,
        titleKey: 'mirrorStartFailed',
        descriptionKey: 'connectionTimeoutHint',
        rawError: rawError,
      );
    }

    // 4. 连接被拒绝
    if (lower.contains('connection refused') || lower.contains('refused')) {
      return MirrorErrorInfo(
        type: MirrorErrorType.connectionRefused,
        titleKey: 'mirrorStartFailed',
        descriptionKey: 'connectionRefusedHint',
        rawError: rawError,
      );
    }

    // 5. 其它一般性异常
    return MirrorErrorInfo(
      type: MirrorErrorType.general,
      titleKey: 'mirrorStartFailed',
      descriptionKey: 'mirrorStartFailed',
      fallbackDescription: rawError,
      rawError: rawError,
    );
  }
}
