import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/process/process_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/processes/processes_tab.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedPackagesNotifier extends PackagesNotifier {
  _FixedPackagesNotifier() : super('test-device');

  @override
  AsyncValue<List<AdbPackage>> build() => const AsyncValue.data(<AdbPackage>[]);
}

class _RecordingAdbService extends AdbService {
  _RecordingAdbService() : super(executable: 'adb');

  final List<List<String>> shellCommands = [];

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    shellCommands.add(List<String>.from(args));
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  testWidgets('process row exposes stop action only from secondary click', (
    WidgetTester tester,
  ) async {
    const device = AdbDevice(
      id: 'test-device',
      status: 'device',
      model: 'Test Device',
      product: 'test',
      transportId: '1',
    );
    final process = AdbProcess(
      pid: '20693',
      user: 'u0_a330',
      cpu: '10.3',
      memory: '457M',
      cpuTime: '2:41.73',
      name: 'com.example.app',
    );
    final adb = _RecordingAdbService();

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
          ).overrideWith((ref) => Future.value(<AdbProcess>[process])),
          packagesProvider(device.id).overrideWith(_FixedPackagesNotifier.new),
          processServiceProvider.overrideWithValue(ProcessService(adb)),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: const Scaffold(
            body: ProcessesTab(device: device, isVisible: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(CupertinoIcons.xmark), findsNothing);

    await tester.tap(
      find.text(process.name),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(find.text('停止该进程'), findsOneWidget);

    await tester.tap(find.text('停止该进程'));
    await tester.pumpAndSettle();

    expect(
      find.text('确定结束进程 ${process.name} (PID: ${process.pid}) 吗？'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();

    expect(adb.shellCommands, <List<String>>[
      <String>['am', 'force-stop', process.name],
    ]);
    await tester.pump(const Duration(seconds: 2));
  });
}
