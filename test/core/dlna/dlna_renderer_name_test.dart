import 'package:any_deck/core/dlna/dlna_protocol.dart';
import 'package:any_deck/core/dlna/dlna_renderer_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('未启动接收服务时更新名称并同步原生播放器标题', () async {
    const channel = MethodChannel('any_deck/dlna_player');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? title;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setTitle') title = call.arguments as String;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final service = DlnaRendererService.instance;
    await service.setServerName(' 客厅电视 ');
    expect(service.serverName, '客厅电视');
    expect(title, '客厅电视');

    await service.setServerName('  ');
    expect(service.serverName, DlnaProtocol.serverName);
    expect(title, DlnaProtocol.serverName);
  });
}
