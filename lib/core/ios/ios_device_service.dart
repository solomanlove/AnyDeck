import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../adb/adb_device.dart';
import '../adb/adb_result.dart';
import '../dal/rust_dal_bridge.dart';
import '../process/tool_path_resolver.dart';
import 'ios_device_identity.dart';
import 'ios_connection_type.dart';
import 'ios_usb_mirror_service.dart';

/// 负责管理 go-ios 进程、解析设备列表以及管理 iOS 投屏会话。
class IosDeviceService {
  IosDeviceService({
    void Function(String message, {String tag, String level})? onLog,
  }) : _onLog = onLog;

  final void Function(String message, {String tag, String level})? _onLog;
  final usbMirror = IosUsbMirrorService();
  bool _useNativeDiscovery = true;

  /// 检索可用 go-ios 二进制路径。
  String _resolveBinary() {
    final pathIos = resolveToolPath('ios');
    if (pathIos != 'ios' && File(pathIos).existsSync()) {
      return pathIos;
    }
    final pathGoIos = resolveToolPath('go-ios');
    if (pathGoIos != 'go-ios' && File(pathGoIos).existsSync()) {
      return pathGoIos;
    }
    return 'ios'; // 回退至系统 PATH
  }

  /// 获取已连接的 iOS 设备列表。
  Future<List<AdbDevice>> listDevices() async {
    if (_useNativeDiscovery && RustDalBridge.instance.isAvailable) {
      final nativeList = await RustDalBridge.instance.listIosDevices();
      if (nativeList.isNotEmpty) {
        if (nativeList.every((item) => item.containsKey('connection_type'))) {
          // Rust 与 CLI 共用解析规则，保持型号、版本和连接通道一致。
          return parseDeviceListOutput(jsonEncode(nativeList));
        }
        // 旧版动态库丢弃 ConnectionType，后续直接走 CLI，避免持续双重扫描。
        _useNativeDiscovery = false;
      }
    }

    final exe = _resolveBinary();
    try {
      final result = await Process.run(exe, ['list', '--details']);
      if (result.exitCode != 0) {
        _onLog?.call('go-ios list 失败，退出码: ${result.exitCode}, stderr: ${result.stderr}', tag: 'ios', level: 'W');
        return [];
      }
      
      return parseDeviceListOutput(result.stdout);
    } on ProcessException catch (e) {
      _onLog?.call('未能启动 go-ios 进程，请检查是否正确安装：${e.message}', tag: 'ios', level: 'W');
    } catch (e) {
      _onLog?.call('解析 go-ios 设备列表失败: $e', tag: 'ios', level: 'E');
    }
    return [];
  }

  /// 解析 go-ios 输出的设备列表，过滤日志并按 UDID 去重。
  static List<AdbDevice> parseDeviceListOutput(String output) {
    final lines = LineSplitter.split(output);
    final devices = <AdbDevice>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      try {
        final dynamic decoded = jsonDecode(trimmed);
        List<dynamic> list = [];
        if (decoded is List) {
          list = decoded;
        } else if (decoded is Map) {
          if (decoded.containsKey('level')) continue;
          final deviceList =
              decoded['deviceList'] ?? decoded['devices'] ?? decoded['data'];
          if (deviceList is List) {
            list = deviceList;
          } else if (decoded.containsKey('UniqueIdentifier') ||
              decoded.containsKey('Udid') ||
              decoded.containsKey('udid')) {
            list = [decoded];
          }
        }

        for (final item in list) {
          if (item is Map) {
            if (item.containsKey('level')) continue;
            final udid = (item['Udid'] ??
                    item['udid'] ??
                    item['UniqueIdentifier'] ??
                    '')
                .toString();
            if (udid.isEmpty) continue;

            // 同一 UDID 的 USB 与 Network 合并展示，不能丢掉另一条通道。
            final index = devices.indexWhere((d) => d.id == udid);
            final previous = index < 0 ? null : devices[index];
            final connectionType = IosConnectionType.parse(
              item['ConnectionType'] ?? item['connection_type'],
            );

            final name =
                (item['ProductName'] ?? item['name'] ?? '').toString();
            final type =
                (item['ProductType'] ?? item['type'] ?? item['model'] ?? '').toString();
            final version =
                (item['ProductVersion'] ?? item['version'] ?? 'iOS').toString();

            final modelName = IosDeviceIdentity.modelName(type, fallback: name);
            final device = AdbDevice(
              id: udid,
              status: 'device',
              model: modelName ?? previous?.model,
              product: IosDeviceIdentity.versionNumber(version) ?? previous?.product,
              transportId: '',
              isIos: true,
              iosConnectionTypes: Set.unmodifiable({
                ...?previous?.iosConnectionTypes,
                ?connectionType,
              }),
            );
            if (index < 0) {
              devices.add(device);
            } else {
              devices[index] = device;
            }
          }
        }
      } catch (_) {
        // 忽略非目标 JSON 结构或警告日志行的解析失败
      }
    }
    return devices;
  }

  /// 检测某个设备是否处于活跃投屏会话中。
  bool isActive(String udid) => usbMirror.texture(udid) != null;

  /// 获取指定设备的原生 Texture ID（保留旧调用入口名称）。
  int? getPort(String udid) => usbMirror.texture(udid);

  /// 自动下载并挂载 iOS 开发者镜像 (Developer Disk Image)
  Future<AdbResult> mountDeveloperImage(String udid) async {
    final exe = _resolveBinary();
    _onLog?.call('正在为 iOS 设备挂载开发者镜像: $exe image auto --udid=$udid', tag: 'ios', level: 'I');
    try {
      final result = await Process.run(exe, ['image', 'auto', '--udid=$udid']).timeout(const Duration(seconds: 45));
      final combined = '${result.stdout}\n${result.stderr}';
      if (combined.contains('DeviceLocked') ||
          combined.contains('failed to read response for \'ReceiveBytes\'') ||
          combined.contains('failed to read message length: EOF') ||
          combined.contains('wrong payload length')) {
        return const AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: 'iPhone 处于锁屏状态，请在手机上输入密码解锁屏幕并保持亮屏，然后重试',
        );
      }
      
      // 检查挂载结果
      final listRes = await Process.run(exe, ['image', 'list', '--udid=$udid']);
      final listOut = listRes.stdout.toString();
      if (listRes.exitCode == 0 && !listOut.contains('"none"') && !listOut.contains('[]')) {
        _onLog?.call('开发者镜像挂载成功', tag: 'ios', level: 'I');
        return const AdbResult(exitCode: 0, stdout: '开发者镜像挂载成功', stderr: '');
      }

      String errorDetail = '挂载开发者镜像失败';
      if (combined.contains('"err":')) {
        try {
          final lines = LineSplitter.split(combined);
          for (final line in lines) {
            if (line.contains('"err":')) {
              final decoded = jsonDecode(line);
              if (decoded is Map && decoded['err'] != null) {
                errorDetail = decoded['err'].toString();
                break;
              }
            }
          }
        } catch (_) {}
      }

      return AdbResult(
        exitCode: 1,
        stdout: result.stdout.toString(),
        stderr: errorDetail,
      );
    } catch (e) {
      return AdbResult(exitCode: 1, stdout: '', stderr: '挂载开发者镜像失败: $e');
    }
  }

  /// 原生采集会话由当前 Flutter Engine 持有；不再创建截图流和固定端口。
  Future<int> startMirroring({required String udid}) => usbMirror.start(udid);

  Future<void> stopMirroring(String udid) => usbMirror.stop(udid);

  void stopAll() => usbMirror.stopAll();
}
