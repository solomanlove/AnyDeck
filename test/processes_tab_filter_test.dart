import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/process/process_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/processes/processes_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedPackagesNotifier extends PackagesNotifier {
  final List<AdbPackage> packages;
  _FixedPackagesNotifier({required this.packages}) : super('test-device');

  @override
  AsyncValue<List<AdbPackage>> build() => AsyncValue.data(packages);
}

class _DummyAdbService extends AdbService {
  _DummyAdbService() : super(executable: 'adb');

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  testWidgets('processes tab filters user processes by default, and switches to system / all', (
    WidgetTester tester,
  ) async {
    const device = AdbDevice(
      id: 'test-device',
      status: 'device',
      model: 'Test Device',
      product: 'test',
      transportId: '1',
    );

    final userAppProcess = AdbProcess(
      pid: '2200',
      user: 'u0_a331',
      cpu: '3.2',
      memory: '351M',
      cpuTime: '0:48.69',
      name: 'com.ss.android.ugc.aweme',
    );

    final userAppSubProcess = AdbProcess(
      pid: '3606',
      user: 'u0_a331',
      cpu: '0.0',
      memory: '86M',
      cpuTime: '0:00.87',
      name: 'com.ss.android.ugc.aweme:sandboxed_process0',
    );

    final systemAppProcess = AdbProcess(
      pid: '6970',
      user: 'u0_a227',
      cpu: '3.2',
      memory: '341M',
      cpuTime: '362:46.62',
      name: 'com.android.systemui',
    );

    final allProcesses = [userAppProcess, userAppSubProcess, systemAppProcess];

    final packages = [
      const AdbPackage(
        name: 'com.ss.android.ugc.aweme',
        label: '抖音',
        system: false,
      ),
      const AdbPackage(
        name: 'com.android.systemui',
        label: '系统界面',
        system: true,
      ),
    ];

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceOnlineProvider(device.id).overrideWithValue(true),
          processesProvider(
            device.id,
          ).overrideWith((ref) => Future.value(allProcesses)),
          packagesProvider(
            device.id,
          ).overrideWith(() => _FixedPackagesNotifier(packages: packages)),
          processServiceProvider.overrideWithValue(ProcessService(_DummyAdbService())),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: Scaffold(
            body: ProcessesTab(device: device, isVisible: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 默认显示用户进程：抖音 与 抖音子进程可见，系统界面不可见
    expect(find.text('抖音'), findsOneWidget);
    expect(find.text('com.ss.android.ugc.aweme:sandboxed_process0'), findsOneWidget);
    expect(find.text('系统界面'), findsNothing);
    expect(find.textContaining('共 2 个进程'), findsOneWidget);

    // 切换到“系统进程”
    await tester.tap(find.text('系统进程'));
    await tester.pumpAndSettle();

    // 系统界面可见，用户应用不可见
    expect(find.text('系统界面'), findsOneWidget);
    expect(find.text('抖音'), findsNothing);
    expect(find.text('com.ss.android.ugc.aweme:sandboxed_process0'), findsNothing);
    expect(find.textContaining('共 1 个进程'), findsOneWidget);

    // 切换到“全部”
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();

    // 全部可见
    expect(find.text('抖音'), findsOneWidget);
    expect(find.text('com.ss.android.ugc.aweme:sandboxed_process0'), findsOneWidget);
    expect(find.text('系统界面'), findsOneWidget);
    expect(find.textContaining('共 3 个进程'), findsOneWidget);
  });
}
