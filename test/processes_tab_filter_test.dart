import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_icon.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/dashboard_tab_layout.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/apps/app_management_service.dart';
import 'package:any_deck/core/process/process_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/processes/processes_tab.dart';
import 'package:any_deck/features/widgets/dashboard_table_header.dart';
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
    const device = DiscoveredDevice(
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
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
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

  testWidgets('进程表贴合内容区两侧和底边，窄窗口可滚至末列并使用筛选框', (
    WidgetTester tester,
  ) async {
    const device = DiscoveredDevice(
      id: 'test-device',
      status: 'device',
      model: 'Test Device',
      product: 'test',
      transportId: '1',
    );

    final process = AdbProcess(
      pid: '2200',
      user: 'u0_a331',
      cpu: '3.2',
      memory: '39M',
      cpuTime: '0:10.21',
      name: 'com.example.chat',
    );
    tester.view.physicalSize = const Size(1200, 700);
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
          ).overrideWith((ref) => Future.value([process])),
          packagesProvider(device.id).overrideWith(
            () => _FixedPackagesNotifier(
              packages: [AdbPackage(name: process.name)],
            ),
          ),
          processServiceProvider.overrideWithValue(ProcessService(_DummyAdbService())),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Padding(
              // 为侧栏预留空间，确保表宽依据内容区而非整个窗口。
              padding: const EdgeInsets.only(left: 180),
              child: ProcessesTab(device: device, isVisible: false),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tab = find.byType(ProcessesTab);
    final bounds = tester.getRect(tab);
    final toolbar = tester.getRect(
      find.byType(DashboardSearchToolbar<ProcessFilterType>),
    );
    final headers = find.byType(DashboardSortableHeaderCell);
    final row = tester.getRect(find.widgetWithText(InkWell, process.user));
    final listViewport = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Viewport),
    );
    expect(toolbar.left, bounds.left + 16);
    expect(toolbar.right, bounds.right - 16);
    expect(tester.getRect(headers.first).left, bounds.left);
    expect(tester.getRect(headers.last).right, bounds.right);
    expect(row.left, bounds.left);
    expect(row.right, bounds.right);
    expect(tester.getRect(listViewport).bottom, bounds.bottom);

    final tableScroll = find.ancestor(
      of: find.byType(ListView),
      matching: find.byType(SingleChildScrollView),
    );
    final controller = tester
        .widget<SingleChildScrollView>(tableScroll)
        .controller!;
    expect(controller.position.maxScrollExtent, 0);

    // 窗口缩窄后，滚至最右时末列表头和对应数据均在可见区域。
    tester.view.physicalSize = const Size(680, 700);
    await tester.pumpAndSettle();
    expect(tester.getRect(listViewport).bottom, tester.getRect(tab).bottom);
    expect(controller.position.maxScrollExtent, greaterThan(0));
    await tester.drag(tableScroll, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(headers.last).right, tester.getRect(tab).right);
    expect(find.text(process.user).hitTestable(), findsOneWidget);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('用户进程'), findsOneWidget);
    expect(find.text('仅 Debug 应用'), findsNothing);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('筛选 debug 应用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('process row reuses cached app metadata', (
    WidgetTester tester,
  ) async {
    const device = DiscoveredDevice(
      id: 'test-device',
      status: 'device',
      model: 'Test Device',
      product: 'test',
      transportId: '1',
    );
    final appService = AppManagementService(_DummyAdbService());
    appService.memoryCache['cached-device'] = [
      const AdbPackage(name: 'com.example.chat', label: '示例聊天'),
    ];
    final process = AdbProcess(
      pid: '2200',
      user: 'u0_a331',
      cpu: '3.2',
      memory: '39M',
      cpuTime: '0:10.21',
      name: 'com.example.chat:push',
    );

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
          ).overrideWith((ref) => Future.value([process])),
          packagesProvider(device.id).overrideWith(
            () => _FixedPackagesNotifier(
              packages: const [AdbPackage(name: 'com.example.chat')],
            ),
          ),
          packageMetadataResolverProvider.overrideWithValue(
            PackageMetadataResolver(appService),
          ),
          processServiceProvider.overrideWithValue(
            ProcessService(_DummyAdbService()),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: Scaffold(
            body: ProcessesTab(device: device, isVisible: false),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('示例聊天:push'), findsOneWidget);
    expect(find.text('com.example.chat:push'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                AppIcons.androidDefaultAppIcon,
      ),
      findsOneWidget,
    );
  });
}
