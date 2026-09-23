import 'dart:async';

import '../../../common/utils/network_util.dart';
import '../../adb/adb_result.dart';
import '../../adb/adb_service.dart';
import '../../device_actions/device_action_service.dart';
import '../../harmony/hdc_service.dart';
import 'registered_device_model.dart';

/// 设备网络连接、断开、无线连接与配对操作服务。
class DeviceRegistryActions {
  /// 连接指定的网络设备地址（如 IP:端口）。
  ///
  /// 内部自动进行局域网网段匹配与 Ping 连通性测试诊断，优先 ADB 连接，失败时自动尝试 HDC 无线连接。
  static Future<AdbResult> connectDevice({
    required String address,
    required DeviceActionService deviceActionService,
    required HdcService hdcService,
  }) async {
    // 提取 IP 地址
    String ipAddress = address;
    if (address.contains(':')) {
      ipAddress = address.split(':').first;
    }

    // 1. 先判断方法一：是否在同一局域网网段
    final isSameSegment = await NetworkLanMatcher.isSameSubnet(ipAddress);
    if (!isSameSegment) {
      // 如果网段不同，进入方法二：尝试 Ping 测试
      final isPingable = await NetworkLanMatcher.pingDevice(ipAddress);
      if (!isPingable) {
        return const AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: '连接失败：手机与电脑不在同一网段，且局域网 Ping 测试不通，请检查是否连接了相同的 WiFi。',
        );
      }
    }

    // 2. 优先执行 ADB 连接
    var result = await deviceActionService.connect(address);

    // 如果 ADB 连接失败，尝试作为鸿蒙设备通过 HDC 连接
    if (!result.isSuccess) {
      final hdcResult = await hdcService.connectWireless(address);
      if (hdcResult.isSuccess || hdcResult.stdout.contains('Connect OK')) {
        result = hdcResult;
      }
    }

    // 3. 如果点击连接发现不联通，再判断方法二（进行诊断）
    if (!result.isSuccess) {
      final isPingable = await NetworkLanMatcher.pingDevice(ipAddress);
      if (!isPingable) {
        return const AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: '连接失败：虽然在同一网段，但局域网网络 Ping 测试不联通，请检查手机 WiFi 状态或 AP 隔离设置。',
        );
      } else {
        return const AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: '连接失败：设备在局域网内网络连通，但手机调试端口未响应，请检查手机端是否允许调试。',
        );
      }
    }

    return result;
  }

  /// 断开指定的网络设备连接（自动判定鸿蒙 HDC 还是 Android ADB）。
  static Future<AdbResult> disconnectDevice({
    required String address,
    required List<RegisteredDevice> devices,
    required DeviceActionService deviceActionService,
    required HdcService hdcService,
  }) async {
    final isHarmony = devices.any((d) => d.id == address && d.isHarmony) ||
        address.startsWith('harmony:');
    if (isHarmony) {
      return hdcService.disconnectWireless(address);
    } else {
      return deviceActionService.disconnect(address);
    }
  }

  /// 通过 TCP/IP 无线连接已连接 USB 的设备。
  ///
  /// 实际执行命令：`adb connect $ipAddress:$port` 或 `hdc tconn $ipAddress:$port`。
  static Future<AdbResult> connectWireless({
    required String usbDeviceId,
    required String ipAddress,
    int port = 5555,
    required List<RegisteredDevice> devices,
    required AdbService adbService,
    required HdcService hdcService,
  }) async {
    // 1. 先判断方法一：是否在同一局域网网段
    final isSameSegment = await NetworkLanMatcher.isSameSubnet(ipAddress);
    if (!isSameSegment) {
      // 如果网段不同，进入方法二：尝试 Ping 测试
      final isPingable = await NetworkLanMatcher.pingDevice(ipAddress);
      if (!isPingable) {
        return const AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: '连接失败：手机与电脑不在同一网段，且局域网 Ping 测试不通，请检查是否连接了相同的 WiFi。',
        );
      }
    }

    final isHarmony = devices.any((d) => d.id == usbDeviceId && d.isHarmony);
    final AdbResult connectResult;

    if (isHarmony) {
      // 2. 将鸿蒙 USB 设备切换为 TCP 监听模式
      final tmodeResult = await hdcService.enableTcpMode(usbDeviceId, port: port);
      if (!tmodeResult.isSuccess) {
        return tmodeResult;
      }

      // 3. 延迟等待 1 秒，以确保手机端的服务就绪
      await Future.delayed(const Duration(seconds: 1));

      // 4. 执行 hdc tconn 连接
      connectResult = await hdcService.connectWireless('$ipAddress:$port');
    } else {
      // 2. 将 USB 设备切换为 TCP/IP 监听模式，开启指定端口（默认 5555）
      final tcpipResult = await adbService.run([
        '-s',
        usbDeviceId,
        'tcpip',
        port.toString(),
      ]);
      if (!tcpipResult.isSuccess) {
        return tcpipResult;
      }

      // 3. 延迟等待 1 秒，以确保手机端的 TCP/IP 服务成功启动
      await Future.delayed(const Duration(seconds: 1));

      // 4. 执行 adb connect 连接到该局域网 IP
      connectResult = await adbService.run(['connect', '$ipAddress:$port']);
    }

    // 5. 如果点击连接发现不联通，再判断方法二（进行诊断）
    if (!connectResult.isSuccess && !connectResult.stdout.contains('Connect OK')) {
      final isPingable = await NetworkLanMatcher.pingDevice(ipAddress);
      if (!isPingable) {
        return const AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: '连接失败：虽然在同一网段，但局域网网络 Ping 测试不联通，请检查手机 WiFi 状态或 AP 隔离设置。',
        );
      } else {
        return const AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: '连接失败：设备在局域网内网络连通，但手机无线端口未响应，请检查手机端是否允许调试或重新插拔 USB。',
        );
      }
    }

    return connectResult;
  }

  /// 使用配对码配对设备并自动通过 mDNS 发现端口连接。
  static Future<AdbResult> pairAndConnect({
    required String hostWithPort,
    required String pairingCode,
    required AdbService adbService,
    required DeviceActionService deviceActionService,
    required HdcService hdcService,
  }) async {
    // 1. 执行配对
    final pairResult = await adbService.run(['pair', hostWithPort, pairingCode]);
    if (!pairResult.isSuccess) {
      return pairResult;
    }

    // 2. 配对成功后，尝试自动发现连接端口并连接
    final ip = hostWithPort.split(':').first;

    // 轮询 5 次尝试发现 _adb-tls-connect 服务
    String? connectAddress;
    for (int i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      final servicesResult = await adbService.run(['mdns', 'services']);
      if (servicesResult.isSuccess) {
        final lines = servicesResult.stdout.split('\n');
        for (final line in lines) {
          if (line.contains('_adb-tls-connect._tcp') && line.contains(ip)) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 3) {
              connectAddress = parts[2].trim();
              break;
            }
          }
        }
      }
      if (connectAddress != null) {
        break;
      }
    }

    // 3. 执行连接
    final addressToConnect = connectAddress ?? '$ip:5555';
    final connectResult = await connectDevice(
      address: addressToConnect,
      deviceActionService: deviceActionService,
      hdcService: hdcService,
    );

    return AdbResult(
      exitCode: connectResult.exitCode,
      stdout:
          'Successfully paired to $hostWithPort. Connection result: ${connectResult.message}',
      stderr: connectResult.stderr,
    );
  }
}
