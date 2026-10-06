import 'dart:convert';

import '../device_info/device_overview.dart';
import 'ios_command_service.dart';
import 'ios_overview_details.dart';

/// 读取 iOS 概览：两次有界只读查询并行执行，单项失败保留其它可用字段。
class IosOverviewService {
  IosOverviewService(this._commands);

  final IosCommandService _commands;

  Future<DeviceOverview> load(
    String udid, {
    required String fallbackName,
    String? fallbackVersion,
  }) async {
    final results = await Future.wait([
      _query(['info', '--udid=$udid'], 'ProductType'),
      _query(['diskspace', '--udid=$udid'], 'TotalBytes'),
    ]);
    return parse(
      results[0],
      results[1],
      fallbackName: fallbackName,
      fallbackVersion: fallbackVersion,
    );
  }

  Future<Map<String, dynamic>?> _query(
    List<String> args,
    String expected,
  ) async {
    try {
      final result = await _commands.run(args);
      if (!result.isSuccess) return null;
      // go-ios 可能在数据前输出 WARN；必须识别目标对象，不能把警告当成成功。
      try {
        final value = jsonDecode(result.stdout);
        if (value is Map<String, dynamic> &&
            !value.containsKey('level') &&
            value.containsKey(expected)) {
          return value;
        }
      } catch (_) {}
      for (final line in const LineSplitter().convert(result.stdout)) {
        try {
          final value = jsonDecode(line);
          if (value is Map<String, dynamic> &&
              !value.containsKey('level') &&
              value.containsKey(expected)) {
            return value;
          }
        } catch (_) {}
      }
    } catch (_) {
      // 设备断开、工具缺失等错误不影响另一个独立查询的结果。
    }
    return null;
  }

  /// 将响应收敛为展示白名单；不缓存 IMEI、配对数据或 NonVolatileRAM。
  static DeviceOverview parse(
    Map<String, dynamic>? info,
    Map<String, dynamic>? disk, {
    required String fallbackName,
    String? fallbackVersion,
  }) {
    final data = info ?? const <String, dynamic>{};
    final productType = _string(data['ProductType']);
    final spec = IosModelSpec.byProductType[productType];
    final version = _string(data['ProductVersion']);
    final hardware = data['instruments:hardwareInformation'];
    final cores = hardware is Map
        ? _positiveInt(hardware['numberOfCpus'])
        : null;
    final interfaces = data['instruments:networkInformation'];
    final total = _positiveInt(disk?['TotalBytes']);
    final free = _nonNegativeInt(disk?['FreeBytes']);
    final validDisk = total != null && free != null && free <= total;
    final name = _string(data['DeviceName']);
    return DeviceOverview.fromJson({
      'name': name.isEmpty ? fallbackName : name,
      'brand': 'Apple',
      'manufacturer': 'Apple',
      'model': spec == null
          ? _orUnknown(productType)
          : '${spec.name} ($productType)',
      'deviceCode': _orUnknown(productType),
      // UDID 是通信标识，不能冒充硬件序列号。
      'serial': _orUnknown(_string(data['SerialNumber'])),
      'androidVersion': version.isNotEmpty
          ? 'iOS $version'
          : (fallbackVersion ?? 'iOS'),
      'processor': _orUnknown(_string(data['CPUArchitecture'])),
      'storage': validDisk ? '${_gb(total - free)} / ${_gb(total)}' : '-',
      'macAddress': _orUnknown(_string(data['WiFiAddress'])),
      'iosDetails': IosOverviewDetails(
        productType: productType,
        buildVersion: _string(data['BuildVersion']),
        hardwareModel: _string(data['HardwareModel']),
        cpuCores: cores,
        networkInterfaces: interfaces is Map
            ? interfaces.entries
                  .where((e) => e.value is String)
                  .map((e) => '${e.key}: ${e.value}')
                  .join(', ')
            : '',
        partial: info == null || !validDisk,
      ).toJson(),
    });
  }

  static String _string(Object? value) => value is String ? value.trim() : '';
  static String _orUnknown(String value) => value.isEmpty ? '-' : value;
  static int? _nonNegativeInt(Object? value) {
    final parsed = value is int ? value : int.tryParse('$value');
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  static int? _positiveInt(Object? value) {
    final parsed = _nonNegativeInt(value);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  // 使用十进制 GB，与 iOS 容量展示一致，避免将 GB/GiB 混淆。
  static String _gb(int bytes) =>
      '${(bytes / 1000000000).toStringAsFixed(2)} GB';
}
