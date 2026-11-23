import 'dart:async';
import 'dart:io';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/l10n/tables/app_l10n_service_diagnostics.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/diagnostics/service_diagnostic.dart';
import 'package:any_deck/core/process/bounded_process.dart';
import 'package:any_deck/features/diagnostics/controller/service_diagnostic_checks.dart';
import 'package:any_deck/features/diagnostics/controller/service_diagnostics_controller.dart';
import 'package:any_deck/features/diagnostics/widgets/services_diagnostics_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 使用内存探针记录实际调用，并按需延迟指定服务的响应。
Map<DiagnosticService, DiagnosticCheck> _checks({
  Completer<void>? pending,
  FutureOr<void> Function(DiagnosticService)? onCheck,
}) => {
  for (final id in DiagnosticService.values)
    id: () async {
      if (onCheck != null) await onCheck(id);
      if (pending != null) await pending.future;
      return ServiceDiagnostic(
        service: id,
        status: switch (id) {
          DiagnosticService.hdc => ServiceDiagnosticStatus.missing,
          DiagnosticService.airplay => ServiceDiagnosticStatus.error,
          DiagnosticService.virtualCamera =>
            ServiceDiagnosticStatus.permissionRequired,
          DiagnosticService.dlna => ServiceDiagnosticStatus.disabled,
          DiagnosticService.deviceSessions =>
            ServiceDiagnosticStatus.unsupported,
          _ => ServiceDiagnosticStatus.ready,
        },
      );
    },
};

void main() {
  test('初始不执行检查，诊断快照稳定排序且停用/不支持不计故障', () async {
    var calls = 0;
    final checks = _checks().map(
      (id, check) => MapEntry(id, () async {
        calls++;
        return check();
      }),
    );
    final container = ProviderContainer(
      overrides: [serviceDiagnosticChecksProvider.overrideWithValue(checks)],
    );
    addTearDown(container.dispose);
    final initial = container.read(serviceDiagnosticsProvider);
    expect(initial.entries.length, DiagnosticService.values.length);
    expect(
      initial.entries.every(
        (entry) => entry.status == ServiceDiagnosticStatus.notChecked,
      ),
      isTrue,
    );
    expect(calls, 0);
    await container.read(serviceDiagnosticsProvider.notifier).run();
    final result = container.read(serviceDiagnosticsProvider);
    expect(calls, DiagnosticService.values.length);
    expect(result.issueCount, 3);
    expect(result.checkedAt, isNotNull);
    expect(result.orderedEntries.take(3).map((entry) => entry.service), [
      DiagnosticService.hdc,
      DiagnosticService.airplay,
      DiagnosticService.virtualCamera,
    ]);
  });

  test('不同服务可并发单检，重复请求合并且重检保留其他结果', () async {
    const adb = DiagnosticService.adb;
    const hdc = DiagnosticService.hdc;
    final calls = <DiagnosticService>[];
    final pending = {adb: Completer<void>(), hdc: Completer<void>()};
    final checks = _checks(
      onCheck: (service) async {
        calls.add(service);
        await pending[service]?.future;
      },
    );
    final container = ProviderContainer(
      overrides: [serviceDiagnosticChecksProvider.overrideWithValue(checks)],
    );
    addTearDown(container.dispose);
    final controller = container.read(serviceDiagnosticsProvider.notifier);
    ServiceDiagnosticsState snapshot() =>
        container.read(serviceDiagnosticsProvider);
    ServiceDiagnosticStatus status(DiagnosticService service) => snapshot()
        .entries
        .singleWhere((item) => item.service == service)
        .status;

    final first = controller.runSingle(adb);
    final duplicate = controller.runSingle(adb);
    final second = controller.runSingle(hdc);
    expect(duplicate, same(first));
    expect(status(adb), ServiceDiagnosticStatus.checking);
    expect(status(hdc), ServiceDiagnosticStatus.checking);
    expect(status(DiagnosticService.ios), ServiceDiagnosticStatus.notChecked);

    // 后发的 HDC 先返回；另一个探针仍应保留检查中状态。
    pending[hdc]!.complete();
    await second;
    expect(status(hdc), ServiceDiagnosticStatus.missing);
    expect(status(adb), ServiceDiagnosticStatus.checking);
    expect(snapshot().isChecking, isTrue);
    expect(snapshot().checkedAt, isNotNull);
    pending[adb]!.complete();
    await Future.wait([first, duplicate]);
    expect(status(adb), ServiceDiagnosticStatus.ready);
    expect(status(hdc), ServiceDiagnosticStatus.missing);
    expect(snapshot().isChecking, isFalse);
    expect(snapshot().checkedCount, 2);
    expect(snapshot().issueCount, 1);

    await controller.runSingle(adb);
    expect(calls, [adb, hdc, adb]);
    expect(status(hdc), ServiceDiagnosticStatus.missing);
    expect(snapshot().checkedCount, 2);
    expect(snapshot().issueCount, 1);
  });

  test('单项检测与全量诊断交错时，每个探针只执行一次', () async {
    final pending = Completer<void>();
    final calls = <DiagnosticService>[];
    final container = ProviderContainer(
      overrides: [
        serviceDiagnosticChecksProvider.overrideWithValue(
          _checks(pending: pending, onCheck: calls.add),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(serviceDiagnosticsProvider.notifier);
    final single = controller.runSingle(DiagnosticService.hdc);
    final all = controller.run();
    final overlapping = controller.runSingle(DiagnosticService.adb);
    pending.complete();
    await Future.wait([single, all, overlapping]);
    expect(calls, unorderedEquals(DiagnosticService.values));
    final result = container.read(serviceDiagnosticsProvider);
    expect(result.checkedCount, DiagnosticService.values.length);
    expect(result.issueCount, 3);
    expect(result.isChecking, isFalse);
  });

  test('重复点击合并同一轮，单项超时/原生缺失不会阻断其他结果且错误脱敏', () async {
    final pending = Completer<void>();
    var calls = 0;
    final checks = _checks(pending: pending);
    checks[DiagnosticService.adb] = () async {
      calls++;
      await pending.future;
      throw TimeoutException('token=should-not-leak');
    };
    checks[DiagnosticService.virtualCamera] = () async {
      throw MissingPluginException();
    };
    final container = ProviderContainer(
      overrides: [serviceDiagnosticChecksProvider.overrideWithValue(checks)],
    );
    addTearDown(container.dispose);
    final controller = container.read(serviceDiagnosticsProvider.notifier);
    final first = controller.run();
    final second = controller.run();
    expect(identical(first, second), isTrue);
    expect(container.read(serviceDiagnosticsProvider).isChecking, isTrue);
    pending.complete();
    await first;
    final result = container.read(serviceDiagnosticsProvider);
    expect(calls, 1);
    expect(result.isChecking, isFalse);
    final adb = result.entries.first;
    expect(adb.reasonKey, 'diagnosticsTimeout');
    expect(adb.details.single.value, isNot(contains('should-not-leak')));
    expect(
      result.entries
          .singleWhere(
            (entry) => entry.service == DiagnosticService.virtualCamera,
          )
          .status,
      ServiceDiagnosticStatus.missing,
    );
    expect(
      result.entries
          .singleWhere((entry) => entry.service == DiagnosticService.ios)
          .status,
      ServiceDiagnosticStatus.ready,
    );
    await controller.run();
    expect(calls, 2);
  });

  test('诊断中销毁容器，迟到结果不会写回或泄漏异常', () async {
    final pending = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        serviceDiagnosticChecksProvider.overrideWithValue(
          _checks(pending: pending),
        ),
      ],
    );
    final task = container.read(serviceDiagnosticsProvider.notifier).run();
    container.dispose();
    pending.complete();
    await task;
  });

  test('所有服务与状态具备独立中英文文案', () {
    expect(
      serviceDiagnosticsEn.keys.toSet(),
      serviceDiagnosticsZh.keys.toSet(),
    );
    for (final service in DiagnosticService.values) {
      expect(
        serviceDiagnosticsZh.containsKey('diagnosticsService${service.name}'),
        isTrue,
      );
      expect(
        serviceDiagnosticsEn.containsKey('diagnosticsImpact${service.name}'),
        isTrue,
      );
    }
    for (final status in ServiceDiagnosticStatus.values) {
      expect(
        serviceDiagnosticsZh.containsKey('diagnosticsStatus${status.name}'),
        isTrue,
      );
    }
  });

  test('有界命令返回退出码和独立管道，输出受限且参数不经Shell解释', () async {
    final result = await runBoundedProcess('/bin/echo', [
      r'$(touch no-such-diagnostic-file)',
      'abcdef',
    ], maxOutputBytes: 12);
    expect(result.exitCode, 0);
    expect(result.stdout, r'$(touch no-s');
    final failure = await runBoundedProcess('/bin/sh', [
      '-c',
      'printf ok; printf failure >&2; exit 7',
    ]);
    expect(failure.exitCode, 7);
    expect(failure.stdout, 'ok');
    expect(failure.stderr, 'failure');
  }, skip: Platform.isWindows);

  test('命令超时后实际终止子进程', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'anydeck-diagnosis-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final pid = File('${temporary.path}/pid');
    await expectLater(
      runBoundedProcess('/bin/sh', [
        '-c',
        'printf "%s" "\$\$" > "\$1"; while :; do :; done',
        'probe',
        pid.path,
      ], timeout: const Duration(milliseconds: 100)),
      throwsA(isA<TimeoutException>()),
    );
    final processId = (await pid.readAsString()).trim();
    final alive = await Process.run('/bin/kill', ['-0', processId]);
    expect(alive.exitCode, isNot(0));
  }, skip: Platform.isWindows);

  test('CLI立即关闭输入并静默退出时仍返回退出码并完成管道回收', () async {
    for (var attempt = 0; attempt < 4; attempt++) {
      final result = await runBoundedProcess('/bin/sh', [
        '-c',
        'exec 0<&-; exit 12',
      ]);
      expect(result.exitCode, 12);
      expect(result.stdout, isEmpty);
      expect(result.stderr, isEmpty);
    }
  }, skip: Platform.isWindows);

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      for (final (width, scale) in [
        (320.0, 1.0),
        (320.0, 1.6),
        (1024.0, 1.0),
      ]) {
        testWidgets('$language $brightness $width 字号$scale 单项与全量诊断/详情展开/键盘关闭', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final calls = <DiagnosticService>[];
          final firstAdb = Completer<void>();
          final checks = _checks(onCheck: calls.add);
          checks[DiagnosticService.adb] = () async {
            calls.add(DiagnosticService.adb);
            // CLI 正在更新时，探针已完成但结果仍为 checking，之后可以单项重试。
            if (!firstAdb.isCompleted) {
              await firstAdb.future;
              return const ServiceDiagnostic(
                service: DiagnosticService.adb,
                status: ServiceDiagnosticStatus.checking,
                reasonKey: 'diagnosticsToolBusy',
              );
            }
            return const ServiceDiagnostic(
              service: DiagnosticService.adb,
              status: ServiceDiagnosticStatus.ready,
            );
          };
          final container = ProviderContainer(
            overrides: [
              serviceDiagnosticChecksProvider.overrideWithValue(checks),
            ],
          );
          addTearDown(container.dispose);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                locale: Locale(language),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizationsDelegate(),
                  ...GlobalMaterialLocalizations.delegates,
                ],
                theme: buildAppTheme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: const Scaffold(
                  body: Align(
                    alignment: Alignment.bottomRight,
                    child: ServicesDiagnosticsButton(),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(
            find.byKey(const ValueKey('services-diagnostics-button')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('services-diagnostics-panel')),
            findsOneWidget,
          );
          if (width == 1024 && scale == 1) {
            final panel = find.byKey(
              const ValueKey('services-diagnostics-panel'),
            );
            final run = find.byKey(const ValueKey('services-diagnostics-run'));
            final summary = find.text(
              language == 'zh' ? '尚未诊断' : 'Not diagnosed yet',
            );
            expect(tester.widget(run), isA<FilledButton>());
            expect(
              tester.getTopLeft(run).dx,
              greaterThan(tester.getTopRight(summary).dx),
            );
            expect(
              tester.getTopRight(run).dx,
              closeTo(tester.getTopRight(panel).dx, .1),
            );
            expect(tester.getBottomRight(panel).dy + 16, closeTo(900 - 42, .1));
            expect(
              tester
                  .getSize(find.byKey(const ValueKey('diagnostic-row-adb')))
                  .height,
              lessThanOrEqualTo(36),
            );
          }
          expect(container.read(serviceDiagnosticsProvider).checkedAt, isNull);
          final guide = find.text(
            language == 'zh'
                ? '打开安装与配置引导'
                : 'Open installation & configuration guide',
          );
          final details = find.byKey(const ValueKey('diagnostic-details-adb'));
          await tester.tap(details);
          await tester.pumpAndSettle();
          expect(guide, findsOneWidget);
          await tester.tap(details);
          await tester.pumpAndSettle();
          expect(guide, findsNothing);
          expect(calls, isEmpty);

          final row = find.byKey(const ValueKey('diagnostic-row-adb'));
          final run = find.byKey(const ValueKey('services-diagnostics-run'));
          await tester.tap(row);
          await tester.pump();
          expect(guide, findsOneWidget);
          expect(tester.widget<FilledButton>(run).onPressed, isNull);
          await tester.tap(row);
          await tester.pump();
          expect(calls, [DiagnosticService.adb]);

          firstAdb.complete();
          await tester.pumpAndSettle();
          final total = DiagnosticService.values.length;
          final partial = find.text(
            language == 'zh' ? '已检查 1/$total 项' : '1 of $total checked',
          );
          expect(partial, findsOneWidget);
          expect(tester.widget<FilledButton>(run).onPressed, isNotNull);
          await tester.tap(row);
          await tester.pumpAndSettle();
          expect(calls, [DiagnosticService.adb, DiagnosticService.adb]);
          expect(find.text(language == 'zh' ? '已就绪' : 'Ready'), findsOneWidget);
          expect(partial, findsOneWidget);
          expect(
            find.text(language == 'zh' ? '未发现问题' : 'No issues found'),
            findsNothing,
          );

          final airplay = find.byKey(const ValueKey('diagnostic-row-airplay'));
          await tester.ensureVisible(airplay);
          await tester.tap(airplay);
          await tester.pumpAndSettle();
          expect(
            find.text(
              language == 'zh' ? '已检查 2/$total 项' : '2 of $total checked',
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              tester
                  .element(run)
                  .l10n
                  .t('diagnosticsIssueCount')
                  .replaceAll('{count}', '1'),
            ),
            findsOneWidget,
          );

          calls.clear();
          await tester.tap(run);
          await tester.pumpAndSettle();
          expect(calls, unorderedEquals(DiagnosticService.values));
          expect(container.read(serviceDiagnosticsProvider).issueCount, 3);
          final hdc = find.byKey(const ValueKey('diagnostic-details-hdc'));
          await tester.ensureVisible(hdc);
          await tester.tap(hdc);
          await tester.pumpAndSettle();
          expect(guide, findsOneWidget);
          expect(calls, hasLength(DiagnosticService.values.length));
          expect(tester.takeException(), isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('services-diagnostics-panel')),
            findsNothing,
          );
          expect(container.read(serviceDiagnosticsProvider).issueCount, 3);
        });
      }
    }
  }
}
