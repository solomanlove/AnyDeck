import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// 本机接收端身份：只保存随机安装 UUID，不读取硬件序列号或 MAC。
class ReceiverIdentity {
  const ReceiverIdentity({required this.uuid, required this.computerName});

  static const preferenceKey = 'settings.receiverIdentityUuid';
  static Future<ReceiverIdentity>? _loading;
  final String uuid;
  final String computerName;

  String get shortCode =>
      uuid.replaceAll('-', '').substring(0, 6).toUpperCase();

  /// 同一 Isolate 的并发请求复用初始化；窗口间由主窗口负责首次创建。
  static Future<ReceiverIdentity> load({
    SharedPreferences? preferences,
    Future<String> Function()? computerNameReader,
  }) {
    if (preferences != null || computerNameReader != null) {
      return _read(preferences, computerNameReader);
    }
    return _loading ??= _read(null, null).whenComplete(() => _loading = null);
  }

  static Future<ReceiverIdentity> _read(
    SharedPreferences? preferences,
    Future<String> Function()? computerNameReader,
  ) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    var uuid = prefs.getString(preferenceKey) ?? '';
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(uuid)) {
      final random = Random.secure();
      final bytes = List.generate(16, (_) => random.nextInt(256));
      bytes[6] = (bytes[6] & 0x0f) | 0x40;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      uuid =
          '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
          '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
      if (!await prefs.setString(preferenceKey, uuid)) {
        throw StateError('Cannot persist AnyDeck receiver identity');
      }
    }
    String name;
    try {
      name = await (computerNameReader ?? _readComputerName)();
    } catch (_) {
      name = '';
    }
    return ReceiverIdentity(
      uuid: uuid.toLowerCase(),
      computerName: cleanName(name),
    );
  }

  /// 去掉控制字符和 .local，保留系统电脑名称中的中文与空格。
  static String cleanName(String name) {
    final clean = String.fromCharCodes(
      name.runes.where((rune) => rune >= 32 && !(rune >= 127 && rune <= 159)),
    ).trim().replaceFirst(RegExp(r'\.local\.?$', caseSensitive: false), '');
    return {
          'localhost',
          'localhost.localdomain',
          'unknown',
          '(none)',
        }.contains(clean.toLowerCase())
        ? ''
        : clean;
  }

  static Future<String> _readComputerName() async {
    if (Platform.isMacOS) {
      Process? process;
      try {
        final starting = Process.start('/usr/sbin/scutil', [
          '--get',
          'ComputerName',
        ]);
        process = await starting.timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            unawaited(
              starting
                  .then((lateProcess) async {
                    unawaited(lateProcess.stdout.drain<void>());
                    unawaited(lateProcess.stderr.drain<void>());
                    await _stopProcess(lateProcess);
                  })
                  .catchError((_) {}),
            );
            throw TimeoutException('Computer name lookup timed out');
          },
        );
        final output = process.stdout.transform(utf8.decoder).join();
        unawaited(process.stderr.drain<void>());
        final exitCode = await process.exitCode.timeout(
          const Duration(seconds: 2),
        );
        final name = await output.timeout(const Duration(milliseconds: 200));
        if (exitCode == 0 && cleanName(name).isNotEmpty) return name;
      } catch (_) {
        // 系统名称不可读时继续使用 hostname，仍不可读则由稳定短码兜底。
      } finally {
        if (process != null) await _stopProcess(process);
      }
    }
    return Platform.isWindows
        ? Platform.environment['COMPUTERNAME'] ?? Platform.localHostname
        : Platform.localHostname;
  }

  /// 超时和正常结束都回收 CLI；极端情况下升级为 SIGKILL，避免残留进程。
  static Future<void> _stopProcess(Process process) async {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(milliseconds: 200));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(const Duration(milliseconds: 200));
    }
  }
}
