import 'package:any_deck/core/ios/ios_connection_type.dart';
import 'package:any_deck/features/devices/model/device_context_action.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_context_menu_fixture.dart';

void main() {
  test('Android 和 HarmonyOS 在线开放全部常用操作，离线保留设备信息与编辑', () {
    for (final device in [deviceMenuAndroid, deviceMenuHarmony]) {
      expect(
        DeviceContextAction.values.every(
          (action) => action.isEnabledFor(device),
        ),
        isTrue,
      );
    }
    expect(
      DeviceContextAction.values.where(
        (action) => action.isEnabledFor(deviceMenuOffline),
      ),
      [DeviceContextAction.overview, DeviceContextAction.edit],
    );
  });

  test('iOS 隐藏终端，USB 才能从列表新开普通投屏窗口', () {
    expect(DeviceContextAction.terminal.isVisibleFor(deviceMenuIos), isFalse);
    expect(DeviceContextAction.screenshot.isEnabledFor(deviceMenuIos), isTrue);
    expect(DeviceContextAction.mirror.isEnabledFor(deviceMenuIos), isTrue);
    final wireless = deviceMenuIos.copyWith(
      iosConnectionTypes: {IosConnectionType.network},
    );
    expect(DeviceContextAction.screenshot.isEnabledFor(wireless), isTrue);
    expect(DeviceContextAction.mirror.isEnabledFor(wireless), isFalse);
    expect(
      DeviceContextAction.mirror.isEnabledFor(
        wireless,
        hasAirPlaySession: true,
      ),
      isTrue,
    );
  });

  test('只有 AirPlay LIVE 的注册设备不能执行 go-ios 截图或文件操作', () {
    final airplayOnly = deviceMenuIos.copyWith(iosConnectionTypes: {});
    expect(DeviceContextAction.screenshot.isEnabledFor(airplayOnly), isFalse);
    expect(DeviceContextAction.files.isEnabledFor(airplayOnly), isFalse);
    expect(
      DeviceContextAction.mirror.isEnabledFor(
        airplayOnly,
        hasAirPlaySession: true,
      ),
      isTrue,
    );
    final synthetic = airplayOnly.copyWith(id: 'airplay-client');
    expect(
      DeviceContextAction.values.where(
        (action) => action.isVisibleFor(synthetic),
      ),
      [DeviceContextAction.mirror],
    );
  });
}
