import 'dart:async';
import 'dart:convert';

import 'package:any_deck/features/mcp/controller/mcp_audit_log_controller.dart';
import 'package:any_deck/features/mcp/models/mcp_audit_log_entry.dart';
import 'package:any_deck/features/mcp/data/mcp_audit_log_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// 用确定性的存储挂起点验证写入顺序，不依赖延时或实际磁盘速度。
class _DelayedStore extends InMemorySharedPreferencesStore {
  _DelayedStore() : super.empty();
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.setValue(type, key, value);
  }
}

class _FailOnceStore extends InMemorySharedPreferencesStore {
  _FailOnceStore() : super.empty();
  bool failed = false;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (!failed) {
      failed = true;
      throw StateError('test write failed');
    }
    return super.setValue(type, key, value);
  }
}

/// 审计历史的恢复、容量与清空顺序回归，不依赖桌面应用。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer createContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  void record(McpAuditLogNotifier notifier, {String name = 'list_files'}) {
    notifier.recordLog(
      method: 'tools/call',
      toolName: name,
      arguments: {
        'platform': 'android',
        'deviceId': 'private-device',
        'text': 'private-input',
        'localPath': '/private/file',
      },
      isSuccess: true,
      errorMessage: null,
      durationMs: 12,
    );
  }

  test('重新创建 Provider 后恢复脱敏摘要且不保存原始参数', () async {
    final first = createContainer();
    final notifier = first.read(mcpAuditLogProvider.notifier);
    await notifier.ready;
    record(notifier);
    await notifier.flush();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(McpAuditLogStore.preferencesKey)!;
    expect(raw, isNot(contains('private-')));
    expect(raw, isNot(contains('/private/file')));
    final second = createContainer();
    await second.read(mcpAuditLogProvider.notifier).ready;
    final restored = second.read(mcpAuditLogProvider).single;
    expect(restored.toolName, 'list_files');
    expect(
      restored.timestamp,
      first.read(mcpAuditLogProvider).single.timestamp,
    );
    expect(restored.durationMs, 12);
    expect(restored.arguments, {'platform': 'android'});
    expect(restored.isSuccess, true);
  });

  test('连续调用仅保留最近 200 条并按新到旧恢复', () async {
    final container = createContainer();
    final notifier = container.read(mcpAuditLogProvider.notifier);
    await notifier.ready;
    for (var i = 0; i < 205; i++) {
      record(notifier, name: 'tool_$i');
    }
    await notifier.flush();
    final restored = await McpAuditLogStore().load();
    expect(container.read(mcpAuditLogProvider), hasLength(200));
    expect(restored, hasLength(200));
    expect(restored.first.toolName, 'tool_204');
    expect(restored.last.toolName, 'tool_5');
  });

  test('恢复过程中新增调用不会被历史快照覆盖', () async {
    final store = McpAuditLogStore();
    await store.save([_entry('old')]);
    final container = createContainer();
    final notifier = container.read(mcpAuditLogProvider.notifier);
    record(notifier, name: 'new');
    await notifier.flush();
    expect((await store.load()).map((entry) => entry.toolName), ['new', 'old']);
  });

  test('恢复尚未结束时清空，重建后旧记录不会复活', () async {
    final store = McpAuditLogStore();
    await store.save([_entry('old')]);
    final container = createContainer();
    final notifier = container.read(mcpAuditLogProvider.notifier);
    notifier.clearLogs();
    await notifier.flush();
    expect(container.read(mcpAuditLogProvider), isEmpty);
    expect(await store.load(), isEmpty);
  });

  test('正在写入时清空，旧写入不能覆盖清空结果', () async {
    final platform = _DelayedStore();
    SharedPreferencesStorePlatform.instance = platform;
    final store = McpAuditLogStore();
    final first = store.save([_entry('old')]);
    await platform.started.future;
    final clear = store.save([]);
    platform.release.complete();
    await Future.wait([first, clear]);
    expect(await store.load(), isEmpty);
  });

  test('保存失败保留内存记录且下一次调用可以继续保存', () async {
    SharedPreferencesStorePlatform.instance = _FailOnceStore();
    final container = createContainer();
    final notifier = container.read(mcpAuditLogProvider.notifier);
    await notifier.ready;
    record(notifier, name: 'first');
    await notifier.flush();
    expect(container.read(mcpAuditLogProvider), hasLength(1));
    record(notifier, name: 'second');
    await notifier.flush();
    expect((await McpAuditLogStore().load()).map((entry) => entry.toolName), [
      'second',
      'first',
    ]);
  });

  test('损坏的历史不阻止后续调用保存', () async {
    SharedPreferences.setMockInitialValues({
      McpAuditLogStore.preferencesKey: '{broken',
    });
    final container = createContainer();
    final notifier = container.read(mcpAuditLogProvider.notifier);
    await notifier.ready;
    expect(container.read(mcpAuditLogProvider), isEmpty);
    record(notifier);
    await notifier.flush();
    expect(await McpAuditLogStore().load(), hasLength(1));
    final raw = (await SharedPreferences.getInstance()).getString(
      McpAuditLogStore.preferencesKey,
    )!;
    expect(jsonDecode(raw), isA<List>());
  });
}

McpAuditLogEntry _entry(String name) => McpAuditLogEntry(
  id: name,
  timestamp: DateTime.utc(2026, 11, 17),
  method: 'tools/call',
  toolName: name,
  isSuccess: true,
  durationMs: 1,
);
