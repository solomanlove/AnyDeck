import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/screenshot/controller/screenshot_controller.dart';
import 'package:any_deck/features/screenshot/controller/screenshot_auto_save_writer.dart';
import 'package:any_deck/features/screenshot/controller/screenshot_export_helper.dart';
import 'package:any_deck/features/screenshot/editor/model/screenshot_edit.dart';
import 'package:any_deck/features/screenshot/editor/renderer/screenshot_edit_renderer.dart';
import 'package:any_deck/features/screenshot/model/screenshot_state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_adb_service.dart';

const _deviceId = 'screenshot_edit_device';
final _provider = screenshotLayoutControllerProvider(_deviceId);

/// 使用可挂起的真实截图入口验证异步刷新和编辑会话的竞争关系。
class _CaptureService extends FakeAdbService {
  _CaptureService(this.bytes);

  final Uint8List bytes;
  Completer<Uint8List>? nextRequest;
  int captures = 0;

  @override
  Future<Uint8List> captureScreenshot(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    captures++;
    final pending = nextRequest;
    nextRequest = null;
    return pending == null ? bytes : await pending.future;
  }
}

class _EmptyRegistry extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => const [];
}

/// 仅用于录屏阶段入口验证，其他流程全部使用 ScreenshotController 原实现。
class _RecordingController extends ScreenshotController {
  _RecordingController(this.phase) : super(_deviceId);
  final ScreenRecordPhase phase;

  @override
  ScreenshotLayoutState build() => super.build().copyWith(recordPhase: phase);
}

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(40, 60);
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

Future<ScreenshotEditResult> _edit(ui.Image image) =>
    ScreenshotEditRenderer.render(image, [
      ScreenshotEditMark(
        tool: ScreenshotEditTool.cover,
        points: const [Offset(2, 2), Offset(16, 16)],
        color: Colors.red,
        width: 6,
      ),
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CaptureService service;
  late ProviderContainer container;
  late ScreenshotController controller;
  late ScreenshotAutoSaveWriter saveWriter;
  late ProviderSubscription<ScreenshotLayoutState> subscription;

  setUp(() async {
    service = _CaptureService(await _png());
    saveWriter = ScreenshotExportHelper.autoSaveScreenshot;
    container = ProviderContainer(
      overrides: [
        adbServiceProvider.overrideWithValue(service),
        screenshotAutoSaveWriterProvider.overrideWith((ref) => saveWriter),
        deviceRegistryProvider.overrideWith(_EmptyRegistry.new),
      ],
    );
    subscription = container.listen(_provider, (_, _) {});
    controller = container.read(_provider.notifier);
  });

  tearDown(() {
    subscription.close();
    container.dispose();
  });

  test('编辑冻结画面并丢弃进入编辑前已发出的自动截图', () async {
    await controller.captureScreenshot();
    final original = container.read(_provider);
    final pending = Completer<Uint8List>();
    service.nextRequest = pending;
    final capture = controller.captureScreenshot(isAuto: true);
    expect(container.read(_provider).isLoading, isFalse);

    controller.beginEditing();
    expect(container.read(_provider).isEditing, isTrue);
    pending.complete(service.bytes);
    await capture;

    final frozen = container.read(_provider);
    expect(frozen.isEditing, isTrue);
    expect(frozen.decodedImage, same(original.decodedImage));
    expect(frozen.rawScreenshotBytes, same(original.rawScreenshotBytes));
    await controller.captureScreenshot();
    await controller.captureScreenshot(isAuto: true);
    await controller.loadLayoutAndScreenshot();
    expect(service.captures, 2);
    expect(container.read(_provider).isLoading, isFalse);
  });

  test('慢磁盘保存也占用截图在途锁，切页后的旧保存不计入新会话', () async {
    final entered = Completer<void>();
    final writing = Completer<String?>();
    var writes = 0;
    saveWriter = ({required deviceId, required rawBytes, required targetPath,
      required hostPlatform}) {
      writes++;
      entered.complete();
      return writing.future;
    };
    controller.updateAutoRefreshConfig(autoSave: true, savePath: '/fake',
      intervalSeconds: 1, startImmediately: false);
    final capture = controller.captureScreenshot(isAuto: true);
    await entered.future;
    await controller.captureScreenshot(isAuto: true);
    expect(writes, 1);
    expect(service.captures, 1);
    controller.pauseAutoRefreshForTabSwitch();
    writing.complete('/fake/capture.png');
    await capture;
    expect(container.read(_provider).autoSavedCount, 0);
  });

  test('上一张自动截图未完成时不会并发发起第二张', () async {
    final pending = Completer<Uint8List>();
    service.nextRequest = pending;
    final first = controller.captureScreenshot(isAuto: true);
    final second = controller.captureScreenshot(isAuto: true);
    expect(service.captures, 1);

    pending.complete(service.bytes);
    await Future.wait([first, second]);
    expect(service.captures, 1);
    expect(container.read(_provider).hasImage, isTrue);
  });

  test('最后一个监听者离开后释放解码图片', () async {
    final local = ProviderContainer(
      overrides: [
        adbServiceProvider.overrideWithValue(service),
        screenshotAutoSaveWriterProvider.overrideWith((ref) => saveWriter),
        deviceRegistryProvider.overrideWith(_EmptyRegistry.new),
      ],
    );
    addTearDown(local.dispose);
    final subscription = local.listen(_provider, (_, _) {});
    await local.read(_provider.notifier).captureScreenshot();
    final image = local.read(_provider).decodedImage!;

    subscription.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(image.debugDisposed, isTrue);
  });

  test('开始编辑停止连续截图且切回 Tab 不恢复定时器', () async {
    await controller.captureScreenshot();
    fakeAsync((clock) {
      controller.toggleAutoRefresh();
      expect(container.read(_provider).isAutoRefresh, isTrue);
      controller.beginEditing();
      controller.resumeAutoRefreshAfterTabSwitch();
      clock.elapse(const Duration(seconds: 12));
      expect(container.read(_provider).isEditing, isTrue);
      expect(container.read(_provider).isAutoRefresh, isFalse);
      expect(service.captures, 1);
      expect(clock.periodicTimerCount, 0);
    });
  });

  test('编辑完成优先预览和导出编辑结果并保留原始 PNG', () async {
    await controller.captureScreenshot();
    final original = container.read(_provider);
    controller.beginEditing();
    final result = await _edit(original.displayImage!);
    controller.completeEditing(original.displayImage!, result);

    final edited = container.read(_provider);
    expect(edited.isEditing, isFalse);
    expect(edited.exportBytes, same(result.bytes));
    expect(edited.displayImage, same(result.image));
    expect(edited.rawScreenshotBytes, same(original.rawScreenshotBytes));
    expect(edited.decodedImage, same(original.decodedImage));
    expect(
      edited.exportBytes,
      isNot(orderedEquals(original.rawScreenshotBytes!)),
    );
    expect(edited.imgWidth, 40);
    expect(edited.imgHeight, 60);

    controller.beginEditing();
    controller.cancelEditing();
    expect(container.read(_provider).displayImage, same(result.image));
    expect(container.read(_provider).exportBytes, same(result.bytes));
  });

  test('新的截图成功后清除旧编辑结果并恢复原图导出', () async {
    await controller.captureScreenshot();
    final source = container.read(_provider).displayImage!;
    controller.beginEditing();
    final result = await _edit(source);
    controller.completeEditing(source, result);
    expect(container.read(_provider).editedImage, same(result.image));

    await controller.captureScreenshot();
    final refreshed = container.read(_provider);
    expect(refreshed.editedImage, isNull);
    expect(refreshed.editedScreenshotBytes, isNull);
    expect(refreshed.displayImage, same(refreshed.decodedImage));
    expect(refreshed.exportBytes, same(refreshed.rawScreenshotBytes));
    expect(result.image.debugDisposed, isTrue);
  });

  test('设备重置后迟到的编辑导出被释放且不挂回设备状态', () async {
    await controller.captureScreenshot();
    final source = container.read(_provider).displayImage!;
    controller.beginEditing();
    final result = await _edit(source);
    controller.resetForDeviceSwitch();
    controller.completeEditing(source, result);
    expect(container.read(_provider).hasImage, isFalse);
    expect(container.read(_provider).isEditing, isFalse);
    expect(container.read(_provider).editedImage, isNull);
    expect(result.image.debugDisposed, isTrue);
  });

  test('无截图或正在加载时不能进入编辑', () async {
    controller.beginEditing();
    expect(container.read(_provider).isEditing, isFalse);
    await controller.captureScreenshot();
    final pending = Completer<Uint8List>();
    service.nextRequest = pending;
    final capture = controller.captureScreenshot();
    expect(container.read(_provider).isLoading, isTrue);
    controller.beginEditing();
    expect(container.read(_provider).isEditing, isFalse);
    pending.complete(service.bytes);
    await capture;
  });

  test('工作区移除只取消匹配源图的编辑且 Provider 销毁后清理安全', () async {
    await controller.captureScreenshot();
    final oldSource = container.read(_provider).displayImage!;
    await controller.captureScreenshot();
    final currentSource = container.read(_provider).displayImage!;
    controller.beginEditing();

    controller.abandonEditing(oldSource);
    expect(container.read(_provider).isEditing, isTrue);
    controller.abandonEditing(currentSource);
    expect(container.read(_provider).isEditing, isFalse);
    expect(container.read(_provider).displayImage, same(currentSource));

    final disposedContainer = ProviderContainer(
      overrides: [
        adbServiceProvider.overrideWithValue(service),
        screenshotAutoSaveWriterProvider.overrideWith((ref) => saveWriter),
        deviceRegistryProvider.overrideWith(_EmptyRegistry.new),
      ],
    );
    final disposedSubscription = disposedContainer.listen(_provider, (_, _) {});
    final disposedController = disposedContainer.read(_provider.notifier);
    await disposedController.captureScreenshot();
    final disposedSource = disposedContainer.read(_provider).displayImage!;
    disposedController.beginEditing();
    disposedSubscription.close();
    disposedContainer.dispose();
    expect(
      () => disposedController.abandonEditing(disposedSource),
      returnsNormally,
    );
    expect(disposedController.cancelEditing, returnsNormally);
  });

  for (final phase in ScreenRecordPhase.values.where(
    (phase) => phase != ScreenRecordPhase.idle,
  )) {
    test('录屏阶段 $phase 不能进入编辑', () async {
      final recordingContainer = ProviderContainer(
        overrides: [
          adbServiceProvider.overrideWithValue(service),
        screenshotAutoSaveWriterProvider.overrideWith((ref) => saveWriter),
          deviceRegistryProvider.overrideWith(_EmptyRegistry.new),
          _provider.overrideWith(() => _RecordingController(phase)),
        ],
      );
      addTearDown(recordingContainer.dispose);
      final recordingSubscription = recordingContainer.listen(_provider, (_, _) {});
      addTearDown(recordingSubscription.close);
      final recordingController = recordingContainer.read(_provider.notifier);
      await recordingController.captureScreenshot();
      recordingController.beginEditing();
      expect(recordingContainer.read(_provider).hasImage, isTrue);
      expect(recordingContainer.read(_provider).isEditing, isFalse);
    });
  }

  testWidgets('编辑期间布局、自动截图和录屏入口均不改变设备状态', (tester) async {
    await tester.runAsync(controller.captureScreenshot);
    controller.beginEditing();
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    controller.toggleLayoutAnalysis(true);
    controller.toggleAutoRefresh();
    controller.updateAutoRefreshConfig(
      autoSave: true,
      savePath: '/unused',
      intervalSeconds: 1,
    );
    await controller.startRecording(context: context);
    final state = container.read(_provider);
    expect(state.isLayoutAnalysis, isFalse);
    expect(state.isAutoRefresh, isFalse);
    expect(state.isAutoSave, isFalse);
    expect(state.isRecordingActive, isFalse);
    expect(state.canToggleLayoutAnalysis, isFalse);
    expect(state.cannotToggleReasonKey, 'screenshotEditBlocked');
    expect(service.captures, 1);
  });
}
