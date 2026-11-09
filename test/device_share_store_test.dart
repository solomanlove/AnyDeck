import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/device_share/device_share_invitation.dart';
import 'package:any_deck/core/device_share/device_share_models.dart';
import 'package:any_deck/core/device_share/device_share_store.dart';
import 'package:any_deck/core/device_share/share_tls_identity.dart';
import 'package:flutter_test/flutter_test.dart';

/// 使用独立临时目录验证含凭据的私有存储，不访问真实用户历史。
void main() {
  late ShareTlsIdentity identity;
  late SavedDeviceShare profile;
  late Directory directory;
  late FileDeviceShareStore store;
  setUpAll(() async {
    identity = await ShareTlsIdentity.generate(persistent: true);
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anydeck-share-history-');
    store = FileDeviceShareStore(
      directory: Directory('${directory.path}/private'),
    );
    profile = SavedDeviceShare(
      deviceId: 'phone',
      serial: 'phone',
      name: '测试手机',
      identity: identity,
      token: DeviceShareInvitation.createToken(),
      wifiSsid: 'test-wifi',
      lastHost: '192.0.2.1',
      lastPort: 42345,
      lifetime: DeviceShareLifetime.unlimited,
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('首次读取为空，保存后新实例恢复规则、身份、时间选项和重连历史', () async {
    expect((await store.load()).profiles, isEmpty);
    final code = DeviceShareInvitation(
      host: profile.lastHost!,
      port: profile.lastPort,
      fingerprint: profile.id,
      token: profile.token,
      name: profile.name,
      resumable: true,
    );
    final entry = DeviceShareHistoryEntry(code, DateTime.utc(2026, 11, 9));
    await store.save(
      DeviceShareSavedState(profiles: [profile], history: [entry]),
    );
    final restored = await FileDeviceShareStore(
      directory: store.directory,
    ).load();
    expect(restored.profiles.single.id, profile.id);
    expect(restored.profiles.single.identity.privateKey, identity.privateKey);
    expect(restored.profiles.single.lifetime, DeviceShareLifetime.unlimited);
    expect(restored.profiles.single.automaticallyPrepares, isTrue);
    expect(restored.history.single.invitation.encode(), code.encode());
    expect(restored.history.single.lastConnectedAt, entry.lastConnectedAt);
  });

  test('凭据文件与目录限制为当前用户，写入后没有 pending 文件', () async {
    await store.save(DeviceShareSavedState(profiles: [profile]));
    final root = store.directory!;
    if (!Platform.isWindows) {
      expect((await root.stat()).mode & 0x1ff, 0x1c0);
      expect(
        (await File('${root.path}/state.json').stat()).mode & 0x1ff,
        0x180,
      );
    }
    expect(await File('${root.path}/state.pending').exists(), isFalse);
  });

  test('连续并发保存按请求顺序提交，不产生半份 JSON', () async {
    await Future.wait([
      store.save(DeviceShareSavedState(profiles: [profile])),
      store.save(
        DeviceShareSavedState(profiles: [profile.copyWith(enabled: false)]),
      ),
    ]);
    expect((await store.load()).profiles.single.enabled, isFalse);
  });

  test('损坏文件读取失败时保留原文件，不自动清空历史', () async {
    await store.save(DeviceShareSavedState(profiles: [profile]));
    final file = File('${store.directory!.path}/state.json');
    await file.writeAsString('{broken');
    await expectLater(store.load(), throwsFormatException);
    expect(await file.readAsString(), '{broken');
  });

  test('单条无效记录不影响其他有效规则和历史', () {
    final json = DeviceShareSavedState(profiles: [profile]).toJson();
    final restored = DeviceShareSavedState.fromJson(
      jsonDecode(
            jsonEncode({
              ...json,
              'profiles': [
                null,
                {'name': 'broken'},
                ...json['profiles'] as List,
              ],
            }),
          )
          as Map<String, dynamic>,
    );
    expect(restored.profiles.single.id, profile.id);
  });

  test('三种时长和旧配置的默认值保持明确', () {
    expect(DeviceShareLifetime.minutes30.duration, const Duration(minutes: 30));
    expect(DeviceShareLifetime.hour1.duration, const Duration(hours: 1));
    expect(DeviceShareLifetime.unlimited.duration, isNull);
    expect(DeviceShareLifetime.parse('unknown'), DeviceShareLifetime.minutes30);
    expect(profile.copyWith(clearWifi: true).automaticallyPrepares, isFalse);
    expect(profile.copyWith(enabled: false).automaticallyPrepares, isFalse);
  });

  test('旧分享码可读取，新分享码保留重连与期限但地址可更新', () {
    final legacy = DeviceShareInvitation(
      host: '192.0.2.1',
      port: 1234,
      fingerprint: profile.id,
      token: profile.token,
      name: 'phone',
    );
    expect(DeviceShareInvitation.parse(legacy.encode()).resumable, isFalse);
    final current = DeviceShareInvitation(
      host: legacy.host,
      port: legacy.port,
      fingerprint: profile.id,
      token: profile.token,
      name: 'phone',
      resumable: true,
      expiresAt: DateTime.utc(2026, 11, 9),
    );
    final updated = DeviceShareInvitation.parse(
      current.encode(),
    ).at('192.0.2.2', 4321);
    expect(updated.host, '192.0.2.2');
    expect(updated.resumable, isTrue);
    expect(updated.fingerprint, current.fingerprint);
    expect(updated.expiresAt, current.expiresAt);
  });
}
