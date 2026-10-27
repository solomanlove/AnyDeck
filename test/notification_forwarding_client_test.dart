import 'dart:convert';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/notifications/notification_forwarding_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _NotificationClientAdbFake extends AdbService {
  _NotificationClientAdbFake({
    required this.packageResult,
    this.contentResult = const AdbResult(exitCode: 0, stdout: '', stderr: ''),
  }) : super(executable: 'unused-in-test');

  final AdbResult packageResult;
  final AdbResult contentResult;
  int contentCallCount = 0;

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (args.first == 'pm') return packageResult;
    if (args.first == 'content') {
      contentCallCount++;
      return contentResult;
    }
    throw StateError('Unexpected ADB args: $args');
  }
}

String _payload(Map<String, dynamic> json) =>
    'Result: Bundle[{payload=${base64Encode(utf8.encode(jsonEncode(json)))}}]';

void main() {
  test('当前 Android user 未安装 Companion 时不调用 ContentProvider', () async {
    final adb = _NotificationClientAdbFake(
      packageResult: const AdbResult(exitCode: 0, stdout: '', stderr: ''),
    );
    final client = NotificationForwardingClient(adb);

    final status = await client.getStatus('192.168.31.153:5555', 0);

    expect(status.rawStatus, 'companion_not_installed');
    expect(status.androidUserId, 0);
    expect(status.isReady, isFalse);
    expect(adb.contentCallCount, 0);
  });

  test('ROM 以成功 exit code 返回 Provider 缺失时转换为稳定状态', () async {
    final adb = _NotificationClientAdbFake(
      packageResult: const AdbResult(
        exitCode: 0,
        stdout: 'package:/data/app/com.adbmanage.companion/base.apk',
        stderr: '',
      ),
      contentResult: const AdbResult(
        exitCode: 0,
        stdout: '',
        stderr:
            'Error while accessing provider:com.adbmanage.companion.usage\n'
            'java.lang.IllegalStateException: Could not find provider: '
            'com.adbmanage.companion.usage',
      ),
    );
    final client = NotificationForwardingClient(adb);

    final status = await client.getStatus('device', 0);

    expect(status.rawStatus, 'companion_unavailable');
    expect(status.isReady, isFalse);
    expect(adb.contentCallCount, 1);
  });

  test('当前 Android user 的 Companion 可用时正常解析状态', () async {
    final adb = _NotificationClientAdbFake(
      packageResult: const AdbResult(
        exitCode: 0,
        stdout: 'package:/data/app/com.adbmanage.companion/base.apk',
        stderr: '',
      ),
      contentResult: AdbResult(
        exitCode: 0,
        stdout: _payload({
          'status': 'ok',
          'sharing': true,
          'permission': true,
          'installationId': 'installation-1',
          'androidUserId': 0,
        }),
        stderr: '',
      ),
    );
    final client = NotificationForwardingClient(adb);

    final status = await client.getStatus('device', 0);

    expect(status.rawStatus, 'ok');
    expect(status.installationId, 'installation-1');
    expect(status.isReady, isTrue);
  });
}
