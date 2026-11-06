import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/window/mirror/widget/fusion_app_on_phone_placeholder.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/scrcpy/app_mirror_task_monitor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _packageName = 'com.hihonor.photos';
const _phoneTasks =
    'RootTask id=704 displayId=0\n'
    '  taskId=704: com.hihonor.photos/.GalleryMain\n'
    'RootTask id=800 displayId=123\n';
const _virtualTasks =
    'RootTask id=704 displayId=123\n'
    '  taskId=704: com.hihonor.photos/.GalleryMain\n'
    'RootTask id=800 displayId=0\n';

/// 模拟手机上 Task 在主屏和虚拟副屏之间迁移。
class _AdbFake extends AdbService {
  _AdbFake() : super(executable: 'adb');

  String tasks = _virtualTasks;
  final commands = <List<String>>[];

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(args);
    return AdbResult(exitCode: 0, stdout: tasks, stderr: '');
  }

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(args);
    if (args.contains('move-stack')) {
      tasks = _virtualTasks;
      return const AdbResult(exitCode: 0, stdout: '', stderr: '');
    }
    return AdbResult(exitCode: 0, stdout: tasks, stderr: '');
  }
}

void main() {
  test('同一应用在副屏有 Task 时优先显示真实画面', () {
    final both =
        '$_phoneTasks\nRootTask id=801 displayId=123\n'
        '  taskId=801: com.hihonor.photos/.GalleryMain\n';
    expect(
      locateAppMirrorTask(both, _packageName, 123),
      AppMirrorTaskLocation.virtualDisplay,
    );
    expect(
      locateAppMirrorTask(_phoneTasks, _packageName, 123),
      AppMirrorTaskLocation.phone,
    );
    expect(
      locateAppMirrorTask('RootTask id=800 displayId=123\n', _packageName, 123),
      AppMirrorTaskLocation.missing,
    );
    expect(
      locateAppMirrorTask('', _packageName, 123),
      AppMirrorTaskLocation.unknown,
    );
  });

  test('手机主屏操作立即显示占位，短暂缺失 Task 不闪烁', () async {
    final adb = _AdbFake();
    final monitor = AppMirrorTaskMonitor(
      adbService: adb,
      deviceId: 'honor',
      packageName: _packageName,
      virtualDisplayId: () => 123,
      isReady: () => true,
    );
    addTearDown(monitor.dispose);

    await monitor.checkNow();
    expect(monitor.isAway, false);
    adb.tasks = _phoneTasks;
    await monitor.checkNow();
    expect(monitor.location, AppMirrorTaskLocation.phone);
    expect(monitor.isAway, true);

    adb.tasks = _virtualTasks;
    await monitor.checkNow();
    expect(monitor.isAway, false);
    adb.tasks = 'RootTask id=800 displayId=123\n';
    await monitor.checkNow();
    expect(monitor.isAway, false);
    await monitor.checkNow();
    expect(monitor.location, AppMirrorTaskLocation.missing);
  });

  test('重新启动把手机主屏上的 Task 迁回原虚拟屏', () async {
    final adb = _AdbFake()..tasks = _phoneTasks;
    final monitor = AppMirrorTaskMonitor(
      adbService: adb,
      deviceId: 'honor',
      packageName: _packageName,
      virtualDisplayId: () => 123,
      isReady: () => true,
    );
    addTearDown(monitor.dispose);
    await monitor.checkNow();
    await monitor.restartOnVirtualDisplay();
    expect(
      adb.commands.any(
        (args) =>
            args.contains('move-stack') &&
            args.contains('704') &&
            args.last == '123',
      ),
      true,
    );
    expect(adb.commands.any((args) => args.contains('force-stop')), false);
  });

  for (final (language, brightness) in [
    ('zh', Brightness.light),
    ('en', Brightness.dark),
  ]) {
    testWidgets('应用在手机上时展示名称和重新启动入口 $language', (tester) async {
      var restarts = 0;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: buildAppTheme(brightness),
          home: Scaffold(
            body: FusionAppOnPhonePlaceholder(
              appName: '图库',
              iconPath: null,
              isRestarting: false,
              onRestart: () => restarts++,
            ),
          ),
        ),
      );
      expect(find.text('图库'), findsOneWidget);
      await tester.tap(find.text(language == 'zh' ? '重新启动' : 'Restart'));
      expect(restarts, 1);
    });
  }
}
