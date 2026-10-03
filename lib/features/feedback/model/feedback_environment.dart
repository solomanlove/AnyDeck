import 'dart:ffi';
import 'dart:io';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/providers/modules/registered_device_model.dart';

/// 打开反馈时的环境快照，仅保留版本、型号和连接类型，不导出标识符。
class FeedbackEnvironment {
  const FeedbackEnvironment({
    required this.hostSystem,
    required this.appVersion,
    this.deviceModel,
    this.deviceSystem,
    this.connectionKey,
  });

  final String hostSystem;
  final String appVersion;
  final String? deviceModel;
  final String? deviceSystem;
  final String? connectionKey;

  /// 当前 Flutter 工具链自动从构建参数或 pubspec 注入版本，无需读取源码文件。
  factory FeedbackEnvironment.capture(RegisteredDevice? device) {
    const version = String.fromEnvironment('FLUTTER_BUILD_NAME');
    const build = String.fromEnvironment('FLUTTER_BUILD_NUMBER');
    return FeedbackEnvironment(
      hostSystem:
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion} '
          '(${Abi.current()})',
      appVersion: version.isEmpty
          ? ''
          : '$version${build.isEmpty ? '' : '+$build'}',
      // 不使用 displayName 等可能回退到序列号或用户别名的展示属性。
      deviceModel: device?.model,
      deviceSystem: device?.androidVersion,
      connectionKey: device == null
          ? null
          : device.isIos
          ? 'feedbackUnknown'
          : device.id.startsWith('emulator-')
          ? 'feedbackEmulator'
          : device.isNetwork
          ? 'feedbackNetwork'
          : 'feedbackUsb',
    );
  }

  /// 优先匹配当前在线设备；未选择时只在唯一在线设备存在时自动补全。
  static RegisteredDevice? selectDevice(
    List<RegisteredDevice> devices,
    String? selectedId,
  ) {
    final online = devices.where((device) => device.isOnline).toList();
    if (selectedId != null) {
      for (final device in online) {
        if (device.id == selectedId ||
            device.serial == selectedId ||
            device.connections.contains(selectedId)) {
          // 连接类型应反映当前选中的通道，而非合并记录的首个通道。
          return device.copyWith(id: selectedId);
        }
      }
      return null;
    }
    return online.length == 1 ? online.single : null;
  }

  /// 环境信息直接写入可编辑正文，缺失值明确显示为未获取。
  String format(AppLocalizations l10n) {
    String value(String? text) => text == null || text.trim().isEmpty
        ? l10n.t('feedbackUnknown')
        : text.trim();
    return l10n
        .t('feedbackEnvironmentBody')
        .replaceAll('{system}', hostSystem)
        .replaceAll('{version}', value(appVersion))
        .replaceAll('{model}', value(deviceModel))
        .replaceAll('{deviceSystem}', value(deviceSystem))
        .replaceAll('{connection}', l10n.t(connectionKey ?? 'feedbackUnknown'));
  }
}
