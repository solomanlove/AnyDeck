import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:any_deck/features/mcp/controller/mcp_server_controller.dart';

/// 模拟存储层异常，确保凭据迁移失败时不会开放入口或覆盖旧配置。
class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore() : super.empty();
  @override
  Future<bool> setValue(String type, String key, Object value) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'anydeck_mcp_config_v1';

  Future<McpServerState> initialized(ProviderContainer container) async {
    container.read(mcpServerProvider);
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(Duration.zero);
      final state = container.read(mcpServerProvider);
      if (state.lastError != null || state.registeredTools.isNotEmpty) {
        return state;
      }
    }
    fail('MCP 初始化未完成');
  }

  test('旧配置迁移生成三个独立凭据并持久化，重建后不更换凭据', () async {
    SharedPreferences.setMockInitialValues({
      key: jsonEncode({'enableSse': false}),
    });
    final one = ProviderContainer();
    final state = await initialized(one);
    expect(state.lastError, isNull);
    expect(state.config.enableLegacy, true);
    expect(
      state.config.platformTokens.keys,
      containsAll(['android', 'harmony', 'ios']),
    );
    expect(state.config.platformTokens.values.toSet(), hasLength(3));
    final saved = (await SharedPreferences.getInstance()).getString(key)!;
    expect(jsonDecode(saved)['platformTokens'], state.config.platformTokens);
    one.dispose();
    final two = ProviderContainer();
    try {
      expect(
        (await initialized(two)).config.platformTokens,
        state.config.platformTokens,
      );
    } finally {
      two.dispose();
    }
  });

  test('损坏的旧配置返回错误且保持原文，不能静默重置为宽权限默认值', () async {
    const broken = '{"authToken":"must-not-be-logged"';
    SharedPreferences.setMockInitialValues({key: broken});
    final container = ProviderContainer();
    try {
      final state = await initialized(container);
      expect(state.isRunning, false);
      expect(state.lastError, 'mcpConfigStorageError');
      expect(state.config.platformTokens, isEmpty);
      expect((await SharedPreferences.getInstance()).getString(key), broken);
    } finally {
      container.dispose();
    }
  });

  test('凭据写入失败返回错误，未保存的凭据不可复制或用于启动', () async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = _FailingStore();
    final container = ProviderContainer();
    try {
      final state = await initialized(container);
      expect(state.lastError, 'mcpConfigStorageError');
      expect(state.isRunning, false);
      expect(state.config.platformTokens, isEmpty);
      await container.read(mcpServerProvider.notifier).startServer();
      expect(container.read(mcpServerProvider).isRunning, false);
    } finally {
      container.dispose();
    }
  });
}
