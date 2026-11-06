import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/logcat/logcat_entry.dart';
import 'package:any_deck/core/logcat/logcat_line_reader.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses adb threadtime logcat lines', () {
    const line =
        '05-28 15:18:06.252 25586 25710 W BpBinder: Slow Binder transaction took 211 ms';

    final entry = parseLogcatLine(
      line,
      pidPackages: const {'25586': 'com.android.browser'},
    );

    expect(entry.timestamp, '05-28 15:18:06.252');
    expect(entry.pid, '25586');
    expect(entry.tid, '25710');
    expect(entry.pidTid, '25586-25710');
    expect(entry.level, LogcatLevel.warning);
    expect(entry.tag, 'BpBinder');
    expect(entry.packageName, 'com.android.browser');
    expect(entry.message, 'Slow Binder transaction took 211 ms');
    expect(entry.rawLine, line);
  });

  test('keeps unparsed lines as raw entries', () {
    const line = '--------- beginning of main';

    final entry = parseLogcatLine(line);

    expect(entry.level, LogcatLevel.unknown);
    expect(entry.message, line);
    expect(entry.rawLine, line);
  });

  test('filters visible entries by level, package, tag and text', () {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(logcatControllerProvider.notifier);
    controller.importText('''
05-28 15:18:06.252 25586 25710 W BpBinder: Slow Binder transaction took 211 ms
05-28 15:18:06.253 2778 3270 D NetworkController: 4G level = 5
05-28 15:18:06.254 976 976 E libc: Access denied finding property
''');

    controller.setLevelFilter(LogcatLevelFilter.warning);
    controller.setTagFilter('lib');
    controller.setTextFilter('denied');

    final entries = controller.visibleEntries();

    expect(entries, hasLength(1));
    expect(entries.single.level, LogcatLevel.error);
    expect(entries.single.tag, 'libc');
  });

  test('plain view exposes message content only', () {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(logcatControllerProvider.notifier);
    controller.importText('''
05-28 15:18:06.252 25586 25710 W BpBinder: Slow Binder transaction took 211 ms
--------- beginning of main
''');
    controller.setViewMode(LogcatViewMode.plain);

    expect(controller.visibleLines(), [
      'Slow Binder transaction took 211 ms',
      '--------- beginning of main',
    ]);
  });

  test('大文件按行导入后只保留最近 3000 条', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final directory = await Directory.systemTemp.createTemp('anydeck_logcat_test_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/large.log');
    await file.writeAsString(List.generate(5000, (i) => 'entry $i').join('\n'));

    final controller = container.read(logcatControllerProvider.notifier);
    await controller.importFile(file);

    final entries = container.read(logcatControllerProvider).entries;
    expect(entries, hasLength(3000));
    expect(entries.first.rawLine, 'entry 2000');
    expect(entries.last.rawLine, 'entry 4999');
  });

  test('异常超长行被截断且分块行边界保持正确', () async {
    final lines = await readBoundedLogcatLines(
      Stream.fromIterable(['abc', 'def\n12', '3456789\nlast']),
      maxLineLength: 6,
    ).toList();
    expect(lines, ['abcdef', '123456', 'last']);
  });
}
