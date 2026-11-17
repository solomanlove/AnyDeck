import 'package:any_deck/core/ios/ios_connection_type.dart';
import 'package:any_deck/core/providers/modules/registered_device_model.dart';
import 'package:any_deck/features/devices/model/device_list_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

const _usb = 'phone-usb-serial';
const _tcp = '192.168.1.20:5555';
const _wireless = '192.168.1.20:41117';
const _android = RegisteredDevice(
  id: _usb,
  status: 'device',
  isOnline: true,
  connections: [_usb, _tcp, _wireless],
);

/// 仅验证注册表快照的连接表达，不启动发现、连接或无线准备流程。
void main() {
  test('Android USB、TCPIP 与无线调试同时在线时保留全部通道', () {
    expect(DeviceListPresentation.connections(_android), [
      DeviceConnectionKind.usb,
      DeviceConnectionKind.tcp,
      DeviceConnectionKind.wireless,
    ]);
  });

  test('移除任一连接后仅移除该通道，不把设备简化成单一优先连接', () {
    final cases = [
      (
        [_tcp, _wireless],
        [DeviceConnectionKind.tcp, DeviceConnectionKind.wireless],
      ),
      (
        [_usb, _wireless],
        [DeviceConnectionKind.usb, DeviceConnectionKind.wireless],
      ),
      ([_usb, _tcp], [DeviceConnectionKind.usb, DeviceConnectionKind.tcp]),
    ];
    for (final (channels, expected) in cases) {
      expect(
        DeviceListPresentation.connections(
          _android.copyWith(connections: channels),
        ),
        expected,
        reason: '当前活跃连接：$channels',
      );
    }
    expect(_android.connections, [_usb, _tcp, _wireless]);
  });

  test('重复端点和不同端点属于同类时只显示一次', () {
    final device = _android.copyWith(
      connections: [
        _usb,
        _usb,
        'phone-second-usb-serial',
        _tcp,
        '192.168.1.21:5555',
        _wireless,
        'adb-phone-a1b2._adb-tls-connect._tcp',
      ],
    );
    expect(DeviceListPresentation.connections(device), [
      DeviceConnectionKind.usb,
      DeviceConnectionKind.tcp,
      DeviceConnectionKind.wireless,
    ]);
  });

  for (final status in ['offline', 'unauthorized']) {
    test('$status 不把保留在注册表的历史连接显示为活跃通道', () {
      expect(
        DeviceListPresentation.connections(
          _android.copyWith(status: status, isOnline: false),
        ),
        isEmpty,
      );
      expect(
        DeviceListPresentation.connections(
          _android.copyWith(
            status: status,
            isOnline: false,
            isIos: true,
            iosConnectionTypes: {
              IosConnectionType.usb,
              IosConnectionType.network,
            },
          ),
        ),
        isEmpty,
      );
    });
  }

  test('HDC 的非5555端口仍是TCP，不冒充Android无线调试', () {
    final harmony = _android.copyWith(
      id: '192.168.1.30:8710',
      isHarmony: true,
      connections: ['192.168.1.30:8710'],
    );
    expect(DeviceListPresentation.connections(harmony), [
      DeviceConnectionKind.tcp,
    ]);
    expect(
      DeviceListPresentation.connections(
        harmony.copyWith(connections: [_usb, '192.168.1.30:8710']),
      ),
      [DeviceConnectionKind.usb, DeviceConnectionKind.tcp],
    );
  });

  test('iOS USB与网络通道独立更新，未知通道不能根据UDID猜成USB', () {
    final ios = _android.copyWith(
      id: '00008110-001234567890001E',
      isIos: true,
      iosConnectionTypes: {IosConnectionType.usb, IosConnectionType.network},
    );
    expect(DeviceListPresentation.connections(ios), [
      DeviceConnectionKind.usb,
      DeviceConnectionKind.iosNetwork,
    ]);
    expect(
      DeviceListPresentation.connections(
        ios.copyWith(iosConnectionTypes: {IosConnectionType.network}),
      ),
      [DeviceConnectionKind.iosNetwork],
    );
    expect(
      DeviceListPresentation.connections(
        ios.copyWith(iosConnectionTypes: {IosConnectionType.usb}),
      ),
      [DeviceConnectionKind.usb],
    );
    expect(
      DeviceListPresentation.connections(ios.copyWith(iosConnectionTypes: {})),
      isEmpty,
    );
  });

  test('共享设备只呈现TCP通道，不因本机转发端口或旧连接显示USB和Wi-Fi', () {
    final shared = _android.copyWith(
      id: '127.0.0.1:39871',
      product: 'anydeck_shared_device',
    );
    expect(DeviceListPresentation.connections(shared), [
      DeviceConnectionKind.tcp,
    ]);
    expect(
      DeviceListPresentation.connections(
        shared.copyWith(status: 'offline', isOnline: false),
      ),
      isEmpty,
    );
  });

  test('AirPlay 独立于调试通道，离线时只保留实际投屏状态', () {
    expect(
      DeviceListPresentation.connections(_android, isAirplayMirroring: true),
      [
        DeviceConnectionKind.usb,
        DeviceConnectionKind.tcp,
        DeviceConnectionKind.wireless,
        DeviceConnectionKind.airplay,
      ],
    );
    final offline = _android.copyWith(status: 'offline', isOnline: false);
    expect(
      DeviceListPresentation.connections(offline, isAirplayMirroring: true),
      [DeviceConnectionKind.airplay],
    );
    expect(DeviceListPresentation.connections(offline), isEmpty);
    expect(
      DeviceListPresentation.connections(
        _android.copyWith(isIos: true, iosConnectionTypes: {}),
        isAirplayMirroring: true,
      ),
      [DeviceConnectionKind.airplay],
    );
  });
}
