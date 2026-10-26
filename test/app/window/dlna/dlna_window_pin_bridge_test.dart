import 'package:any_deck/app/window/dlna/controller/dlna_window_pin_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DLNA 标题栏图钉同步状态、文案并响应原生点击', () async {
    const channel = MethodChannel('test/dlna_window_pin');
    const eventsChannel = MethodChannel('test/dlna_window_pin_events');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final bridge = DlnaWindowPinBridge(
      channel: channel,
      eventsChannel: eventsChannel,
    );
    var taps = 0;
    bridge.listen(() async {
      taps++;
    });
    addTearDown(bridge.dispose);

    await bridge.setAlwaysOnTop(true);
    await bridge.update(
      pinned: true,
      pinLabel: '置顶窗口',
      unpinLabel: '取消置顶',
    );
    expect(calls[0].method, 'setAlwaysOnTop');
    expect(calls[0].arguments, isTrue);
    expect(calls[1].method, 'setDlnaPin');
    expect(calls[1].arguments, {
      'pinned': true,
      'pinLabel': '置顶窗口',
      'unpinLabel': '取消置顶',
    });

    await messenger.handlePlatformMessage(
      eventsChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('dlnaPinTapped'),
      ),
      (_) {},
    );
    expect(taps, 1);
  });
}
