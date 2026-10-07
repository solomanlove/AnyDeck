import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/ios/ios_wda_host.dart';

/// 显式设置 UDID 才连接真机；与产品复用相同 WDA 生命周期，不启动桌面 UI。
void main() {
  final udid = Platform.environment['ANYDECK_IOS_POC_UDID'];
  test(
    'iOS 15 WDA device PoC: runner, forwarding, session, geometry, cleanup',
    () async {
      final host = IosWdaHost();
      addTearDown(host.close);
      final result = await host.execute(udid!, 'start', {});
      expect(result['ready'], true);
      expect(result['width'], greaterThan(0));
      expect(result['height'], greaterThan(0));
      // 只有明确指定才发送 Home；默认只读，不猜测坐标点击用户应用。
      if (Platform.environment['ANYDECK_IOS_POC_HOME'] == '1') {
        await host.execute(udid, 'button', {'name': 'home'});
      }
      await host.execute(udid, 'stop', {});
      expect((await host.execute(udid, 'status', {}))['ready'], false);
    },
    skip: udid == null || udid.isEmpty,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
