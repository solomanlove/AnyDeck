import 'package:any_deck/app/window/mirror/mirror_aspect_resolver.dart';
import 'package:any_deck/app/window/mirror/mirror_window_frame_adapter.dart';
import 'package:any_deck/app/window/multi_window_compat.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdbService extends Fake implements AdbService {
  _FakeAdbService(this._shellHandler);
  final Future<AdbResult> Function(String deviceId, String command) _shellHandler;

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration? timeout,
  }) =>
      _shellHandler(deviceId, command);
}

class _FakeHdcService extends Fake implements HdcService {
  _FakeHdcService(this._shellHandler);
  final Future<AdbResult> Function(String deviceId, String command) _shellHandler;

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration? timeout,
  }) =>
      _shellHandler(deviceId, command);
}

void main() {
  group('resolveMirrorInitialWindowSize 窗口尺寸贴合测试', () {
    test('竖屏设备按高度 800 基准计算，消除左右黑边', () {
      // 1080x2400 (ratio = 0.45)
      final size = resolveMirrorInitialWindowSize('1080x2400');
      expect(size.height, 800.0);
      final viewerHeight = size.height - mirrorWindowTopChromeHeight;
      expect(viewerHeight, 770.0);
      final viewerWidth = size.width - mirrorWindowSideChromeWidth;
      expect(viewerWidth, closeTo(770.0 * 0.45, 0.01));
    });

    test('横屏设备按宽度 800 基准计算，具有舒适视野并贴合比例', () {
      // 2400x1080 (ratio = 2400/1080 ≈ 2.2222)
      final size = resolveMirrorInitialWindowSize('2400x1080');
      final viewerWidth = size.width - mirrorWindowSideChromeWidth;
      expect(viewerWidth, 800.0);
      final viewerHeight = size.height - mirrorWindowTopChromeHeight;
      expect(viewerWidth / viewerHeight, closeTo(2400 / 1080, 0.01));
    });

    test('直接指定 ratio 参数优先于 resolution 字符串', () {
      final size = resolveMirrorInitialWindowSize('1080x1920', ratio: 2.0);
      expect(size.width, 800.0 + mirrorWindowSideChromeWidth);
      expect(size.height, 800.0 / 2.0 + mirrorWindowTopChromeHeight);
    });

    test('异常或空分辨率兜底返回默认尺寸', () {
      expect(resolveMirrorInitialWindowSize(null), defaultMirrorWindowSize);
      expect(resolveMirrorInitialWindowSize('-'), defaultMirrorWindowSize);
      expect(resolveMirrorInitialWindowSize('invalid'), defaultMirrorWindowSize);
    });
  });

  group('resolveAppMirrorDisplayResolution 应用副屏尺寸测试', () {
    test('优先复用当前手机投屏视频尺寸', () {
      expect(
        resolveAppMirrorDisplayResolution(
          '1080x1920',
          videoWidth: 1080,
          videoHeight: 2400,
        ),
        '1080x2400',
      );
    });

    test('视频尺寸为奇数时收敛为编码器可用偶数', () {
      expect(
        resolveAppMirrorDisplayResolution(
          null,
          videoWidth: 1081,
          videoHeight: 2401,
        ),
        '1080x2400',
      );
    });

    test('没有活动投屏时保留物理分辨率回退规则', () {
      expect(
        resolveAppMirrorDisplayResolution('1440x3200'),
        '864x1920',
      );
      expect(resolveAppMirrorDisplayResolution(null), '1080x1920');
    });
  });

  group('MirrorWindowFrameAdapter 横竖屏目标尺寸测试', () {
    test('竖屏转横屏时，窗口中心坐标保持不变', () {
      // 原窗口：left=200, top=100, width=400, height=800
      // 标题栏高度 30，内容区域 viewerW=400, viewerH=770
      const oldFrame = Rect.fromLTWH(200, 100, 400, 800);
      final origCenterX = oldFrame.left + oldFrame.width / 2; // 400
      final origCenterY = oldFrame.top + oldFrame.height / 2; // 500

      // 转为横屏，目标宽高比 2.0
      final newFrame = MirrorWindowFrameAdapter.calculateFittedFrame(
        frame: oldFrame,
        aspectRatio: 2.0,
        viewerW: 400,
        viewerH: 770,
      );

      expect(newFrame, isNotNull);
      // 验证旋转后中心点完全保持不变
      final newCenterX = newFrame!.left + newFrame.width / 2;
      final newCenterY = newFrame.top + newFrame.height / 2;
      expect(newCenterX, closeTo(origCenterX, 0.001));
      expect(newCenterY, closeTo(origCenterY, 0.001));

      // 验证新宽度以竖屏高度 viewerH=770 为基准
      expect(newFrame.width, 770.0);
      // 验证新高度包含标题栏
      final newViewerH = newFrame.height - mirrorWindowTopChromeHeight;
      expect(newFrame.width / newViewerH, closeTo(2.0, 0.001));
    });

    test('横屏转竖屏时，窗口中心坐标保持不变', () {
      // 原横屏窗口：left=300, top=200, width=742, height=401 (viewerW=742, viewerH=371)
      const oldFrame = Rect.fromLTWH(300, 200, 742, 401);
      final origCenterX = oldFrame.left + oldFrame.width / 2;
      final origCenterY = oldFrame.top + oldFrame.height / 2;

      // 转为竖屏，目标宽高比 0.5
      final newFrame = MirrorWindowFrameAdapter.calculateFittedFrame(
        frame: oldFrame,
        aspectRatio: 0.5,
        viewerW: 742,
        viewerH: 371,
      );

      expect(newFrame, isNotNull);
      final newCenterX = newFrame!.left + newFrame.width / 2;
      final newCenterY = newFrame.top + newFrame.height / 2;
      expect(newCenterX, closeTo(origCenterX, 0.001));
      expect(newCenterY, closeTo(origCenterY, 0.001));

      // 竖屏基准高度以横屏宽度 viewerW=742 为基准
      final newViewerH = newFrame.height - mirrorWindowTopChromeHeight;
      expect(newViewerH, 742.0);
      expect(newFrame.width, closeTo(742.0 * 0.5, 0.001));
    });

    test('横竖屏适配保留右侧工具栏宽度', () {
      const oldFrame = Rect.fromLTWH(300, 100, 366, 800);
      final newFrame = MirrorWindowFrameAdapter.calculateFittedFrame(
        frame: oldFrame,
        aspectRatio: 2.0,
        viewerW: 334,
        viewerH: 770,
      );

      expect(newFrame, isNotNull);
      final viewerWidth = newFrame!.width - mirrorWindowSideChromeWidth;
      final viewerHeight = newFrame.height - mirrorWindowTopChromeHeight;
      expect(viewerWidth / viewerHeight, closeTo(2.0, 0.001));
      expect(newFrame.width - viewerWidth, mirrorWindowSideChromeWidth);
    });

    test('同方向微调时以中心点进行黑边收敛', () {
      const oldFrame = Rect.fromLTWH(200, 100, 420, 800);
      final origCenterX = oldFrame.left + oldFrame.width / 2;
      final origCenterY = oldFrame.top + oldFrame.height / 2;

      final newFrame = MirrorWindowFrameAdapter.calculateFittedFrame(
        frame: oldFrame,
        aspectRatio: 0.5, // 同为竖屏
        viewerW: 420,
        viewerH: 742,
      );

      expect(newFrame, isNotNull);
      final newCenterX = newFrame!.left + newFrame.width / 2;
      final newCenterY = newFrame.top + newFrame.height / 2;
      expect(newCenterX, closeTo(origCenterX, 0.001));
      expect(newCenterY, closeTo(origCenterY, 0.001));
    });
  });

  group('fetchDeviceAspectRatioBeforeMirror 投屏前宽高比预取测试', () {
    testWidgets('Android 设备能从 dumpsys display 预取宽高比', (tester) async {
      final fakeAdb = _FakeAdbService((deviceId, command) async {
        if (command == 'dumpsys display') {
          return const AdbResult(
            exitCode: 0,
            stdout: '''
  Display 0:
    Viewport INTERNAL: orientation=0 logicalFrame=[0, 0, 1080, 2400]
''',
            stderr: '',
          );
        }
        return const AdbResult(exitCode: 1, stdout: '', stderr: '');
      });

      late WidgetRef widgetRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adbServiceProvider.overrideWithValue(fakeAdb),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              widgetRef = ref;
              return const SizedBox();
            },
          ),
        ),
      );

      final ratio = await MirrorAspectResolver.fetchDeviceAspectRatioBeforeMirror(
        ref: widgetRef,
        deviceId: 'android_dev',
        isHarmony: false,
        isIos: false,
      );

      expect(ratio, closeTo(1080 / 2400, 0.001));
    });

    testWidgets('鸿蒙设备能从 hidumper DisplayManagerService 预取宽高比', (tester) async {
      final fakeHdc = _FakeHdcService((deviceId, command) async {
        if (command.contains('DisplayManagerService')) {
          return const AdbResult(
            exitCode: 0,
            stdout: '''
---------------- Display ID: 0 ----------------
Width: 1224
Height: 2776
Orientation: 0
''',
            stderr: '',
          );
        }
        return const AdbResult(exitCode: 1, stdout: '', stderr: '');
      });

      late WidgetRef widgetRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hdcServiceProvider.overrideWithValue(fakeHdc),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              widgetRef = ref;
              return const SizedBox();
            },
          ),
        ),
      );

      final ratio = await MirrorAspectResolver.fetchDeviceAspectRatioBeforeMirror(
        ref: widgetRef,
        deviceId: 'harmony_dev',
        isHarmony: true,
        isIos: false,
      );

      expect(ratio, closeTo(1224 / 2776, 0.001));
    });
  });
}
