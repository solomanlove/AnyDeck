import 'dart:async';

import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/core/process/tool_path_resolver.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 保留真实加载和通道注册，只隔离与本测试无关的接收端名称初始化。
class _Settings extends AppSettingsController {
  _Settings(this.loaded);

  final Completer<void> loaded;

  @override
  Future<void> ensureReceiverNames() async {
    if (!loaded.isCompleted) loaded.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windows = MethodChannel('mixin.one/desktop_multi_window');
  const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
  const childChannel = 'mixin.one/window_controller/path-sync-child';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      toolPathPreferenceKey('ios'): '/old/ios',
    });
    replaceUserToolPaths({});
    messenger.setMockMethodCallHandler(windows, (call) async {
      if (call.method == 'getWindowDefinition') {
        return {
          'windowId': 'path-sync-child',
          'windowArgument': '{"type":"mirror"}',
        };
      }
      return <Object>[];
    });
  });

  tearDown(() {
    replaceUserToolPaths({});
    messenger.setMockMethodCallHandler(windows, null);
    messenger.setMockMethodCallHandler(channels, null);
  });

  ProviderContainer child(Completer<void> loaded) {
    final scope = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWith(() => _Settings(loaded)),
        windowIdProvider.overrideWithValue('path-sync-child'),
      ],
    );
    addTearDown(scope.dispose);
    scope.read(appSettingsProvider);
    return scope;
  }

  Future<void> deliver(String tool, String path) async {
    final response = await messenger.handlePlatformMessage(
      channels.name,
      channels.codec.encodeMethodCall(
        MethodCall('methodCall', {
          'channel': childChannel,
          'method': 'update_tool_path',
          'arguments': {'tool': tool, 'path': path},
        }),
      ),
      null,
    );
    if (response != null) channels.codec.decodeEnvelope(response);
  }

  test('子窗口等待原生通道就绪再拉取快照，补齐初始化时错过的路径更新', () async {
    final registrationStarted = Completer<void>();
    final registration = Completer<Object?>();
    final requested = Completer<void>();
    messenger.setMockMethodCallHandler(channels, (call) async {
      final arguments = call.arguments as Map;
      if (call.method == 'registerMethodHandler' &&
          arguments['channel'] == childChannel) {
        registrationStarted.complete();
        return registration.future;
      }
      if (call.method == 'invokeMethod' &&
          arguments['method'] == 'resolve_tool_paths') {
        expect(registration.isCompleted, isTrue);
        requested.complete();
        return {'ios': '/new/ios'};
      }
      return null;
    });
    final loaded = Completer<void>();
    final scope = child(loaded);
    final applied = Completer<void>();
    scope.listen(appSettingsProvider, (_, settings) {
      if (settings.toolPaths['ios'] == '/new/ios' && !applied.isCompleted) {
        applied.complete();
      }
    });
    await loaded.future;
    await registrationStarted.future;
    expect(scope.read(appSettingsProvider).toolPaths['ios'], '/old/ios');
    expect(requested.isCompleted, isFalse);
    // 此时主窗口已从旧路径改到新路径，但子窗口通道尚未注册，广播会丢失。
    registration.complete(null);
    await applied.future;
    expect(resolveToolPath('ios'), '/new/ios');
    expect(
      (await SharedPreferences.getInstance()).getString(
        toolPathPreferenceKey('ios'),
      ),
      '/old/ios',
    );
  });

  test('旧快照不覆盖请求期间收到的实时更新，其他工具仍可从快照同步', () async {
    final requested = Completer<void>();
    final snapshot = Completer<Object?>();
    messenger.setMockMethodCallHandler(channels, (call) async {
      final arguments = call.arguments as Map;
      if (call.method == 'invokeMethod' &&
          arguments['method'] == 'resolve_tool_paths') {
        requested.complete();
        return snapshot.future;
      }
      return null;
    });
    final scope = child(Completer<void>());
    final applied = Completer<void>();
    scope.listen(appSettingsProvider, (_, settings) {
      if (settings.toolPaths['hdc'] == '/snapshot/hdc' &&
          !applied.isCompleted) {
        applied.complete();
      }
    });
    await requested.future;
    await deliver('ios', '/live/ios');
    expect(scope.read(appSettingsProvider).toolPaths['ios'], '/live/ios');
    snapshot.complete({'ios': '/old/ios', 'hdc': '/snapshot/hdc'});
    await applied.future;
    expect(scope.read(appSettingsProvider).toolPaths['ios'], '/live/ios');
    expect(resolveToolPath('ios'), '/live/ios');
    expect(resolveToolPath('hdc'), '/snapshot/hdc');
  });
}
