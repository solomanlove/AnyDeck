import 'dart:async';

import '../adb/adb_result.dart';
import '../adb/adb_service.dart';
import 'fusion_display_resize.dart';

enum _DensityMode { display, ratio, unsupported }

/// 管理单个融合副屏的 DPI、串行更新与退出还原，不修改手机内外屏的显示配置。
class FusionDisplayDensity {
  FusionDisplayDensity({
    required this.adbService,
    required this.deviceId,
    required this.displayId,
  }) {
    if (displayId <= 0) {
      throw ArgumentError.value(
        displayId,
        'displayId',
        'Expected a secondary display',
      );
    }
  }

  final AdbService adbService;
  final String deviceId;
  final int displayId;
  Future<_DensityMode>? _mode;
  Future<void> _updates = Future<void>.value();
  Future<bool>? _restoring;
  bool _closed = false;
  bool _mayHaveOverride = false;

  /// 同一会话只探测一次命令能力；排队期间失效的窗口不会再写入 DPI。
  Future<bool> applyWhenResized({
    required FusionDisplayGeometry geometry,
    bool Function()? isCurrent,
  }) {
    final update = _updates.then((_) => _apply(geometry, isCurrent));
    _updates = update.then<void>((_) {}, onError: (_) {});
    return update;
  }

  Future<_DensityMode> _detectMode() async {
    final results = await Future.wait([
      adbService.shellArgs(deviceId, [
        'wm',
        'help',
      ], timeout: const Duration(seconds: 4)),
      adbService.shellArgs(deviceId, [
        'getprop',
        'ro.product.manufacturer',
      ], timeout: const Duration(seconds: 4)),
    ]);
    final help = results[0];
    if (_succeeded(help) &&
        RegExp(
          r'^\s*density[^\n]*\[-r\]',
          multiLine: true,
        ).hasMatch(help.stdout)) {
      // 比例接口只更新目标 DisplayContent，绕过荣耀折叠机普通 DPI 接口的内屏联动。
      return _DensityMode.ratio;
    }
    final manufacturer = results[1].stdout.trim().toLowerCase();
    if (!_succeeded(results[1]) ||
        manufacturer.isEmpty ||
        const {'honor', 'hihonor', 'huawei'}.contains(manufacturer)) {
      // 旧版荣耀/华为缺少独立比例接口时保留初始副屏 DPI，禁止回退到会改内屏的接口。
      return _DensityMode.unsupported;
    }
    return _DensityMode.display;
  }

  Future<bool> _apply(
    FusionDisplayGeometry geometry,
    bool Function()? isCurrent,
  ) async {
    bool current() => !_closed && (isCurrent?.call() ?? true);
    if (!current()) return false;
    final mode = await (_mode ??= _detectMode());
    if (!current() || mode == _DensityMode.unsupported) return false;

    // 等 VirtualDisplay.resize 完成，避免较早的 DPI 设置被尺寸更新覆盖。
    final deadline = Stopwatch()..start();
    final expectedWidth = geometry.width.toString();
    final expectedHeight = geometry.height.toString();
    final physicalSize = RegExp(r'Physical size:\s*(\d+)x(\d+)');
    while (true) {
      if (!current()) return false;
      final size = await adbService.shellArgs(deviceId, [
        'wm',
        'size',
        '-d',
        '$displayId',
      ], timeout: const Duration(seconds: 1));
      final match = physicalSize.firstMatch(size.stdout);
      if (size.isSuccess &&
          match?.group(1) == expectedWidth &&
          match?.group(2) == expectedHeight) {
        break;
      }
      if (deadline.elapsed >= const Duration(seconds: 3)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!current()) return false;
    // 超时并不证明系统未接受设置，发出写入后就由本会话负责还原。
    _mayHaveOverride = true;
    final density = await adbService.shellArgs(deviceId, [
      'wm',
      'density',
      '${geometry.densityDpi}',
      '-d',
      '$displayId',
      if (mode == _DensityMode.ratio) '-r',
    ], timeout: const Duration(seconds: 4));
    return _succeeded(density);
  }

  /// 先阻止迟到更新，再等待已发命令结束；只还原本会话写过的副屏。
  Future<bool> restore() => _restoring ??= _restore();

  Future<bool> _restore() async {
    _closed = true;
    await _updates;
    if (!_mayHaveOverride) return true;
    final result = await adbService.shellArgs(deviceId, [
      'wm',
      'density',
      'reset',
      '-d',
      '$displayId',
    ], timeout: const Duration(seconds: 4));
    return _succeeded(result);
  }

  static bool _succeeded(AdbResult result) =>
      result.isSuccess &&
      !RegExp(
        r'^\s*(Error:|Exception)',
        multiLine: true,
        caseSensitive: false,
      ).hasMatch('${result.stdout}\n${result.stderr}');
}
