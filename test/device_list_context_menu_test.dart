import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:any_deck/core/airplay/airplay_server_state.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/devices/model/device_context_action.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_context_menu_fixture.dart';

Future<void> _rightClick(WidgetTester tester, String name) async {
  await tester.tap(
    find.text(name).first,
    buttons: kSecondaryButton,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

Future<void> _choose(
  WidgetTester tester,
  String label, {
  bool settle = true,
}) async {
  final target = find.widgetWithText(PopupMenuItem<DeviceContextAction>, label);
  await tester.ensureVisible(target);
  await tester.tap(target);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  testWidgets('右键选中当前设备并显示七项常用功能，不进入详情或改变批量勾选', (tester) async {
    await withDeviceMenu(tester, (fixture) async {
      await _rightClick(tester, deviceMenuTarget.displayName);
      for (final label in ['截图', '投屏', '设备信息', '应用', '文件', '终端调试', '编辑设备信息']) {
        expect(
          find.widgetWithText(PopupMenuItem<DeviceContextAction>, label),
          findsOneWidget,
        );
      }
      expect(
        fixture.router.routeInformationProvider.value.uri.path,
        '/devices',
      );
      expect(fixture.container.read(selectedDeviceProvider), isNull);
      expect(
        fixture.container
            .read(deviceRegistryProvider)
            .any((device) => device.isChecked),
        isFalse,
      );
      expect(fixture.adb.captures, isEmpty);
    });
  });

  testWidgets('截图只针对右键设备，保存图片并复制到剪贴板，保持设备列表', (tester) async {
    await withDeviceMenu(tester, (fixture) async {
      await _rightClick(tester, deviceMenuTarget.displayName);
      await _choose(tester, '截图', settle: false);
      await fixture.waitForSavedScreenshot(tester);
      expect(fixture.adb.captures, [deviceMenuTarget.id]);
      expect(fixture.hdc.captures, isEmpty);
      expect(fixture.ios.captures, isEmpty);
      expect(fixture.host.savedFor, [deviceMenuTarget.id]);
      expect(File(fixture.host.savePath!).readAsBytesSync(), deviceMenuImage);
      expect(fixture.host.clipboard, deviceMenuImage);
      expect(
        fixture.router.routeInformationProvider.value.uri.path,
        '/devices',
      );
      expect(find.textContaining('保存成功'), findsOneWidget);
    });
  });

  for (final device in [deviceMenuHarmony, deviceMenuIos]) {
    testWidgets('${device.displayName} 截图走对应平台服务', (tester) async {
      await withDeviceMenu(tester, (fixture) async {
        await _rightClick(tester, device.displayName);
        if (device.isIos) {
          expect(
            find.widgetWithText(PopupMenuItem<DeviceContextAction>, '终端调试'),
            findsNothing,
          );
        }
        await _choose(tester, '截图', settle: false);
        await fixture.waitForSavedScreenshot(tester);
        expect(fixture.adb.captures, isEmpty);
        expect(device.isIos ? fixture.ios.captures : fixture.hdc.captures, [
          device.id,
        ]);
        expect(File(fixture.host.savePath!).readAsBytesSync(), deviceMenuImage);
      });
    });
  }

  testWidgets('离线设备禁用截图等联网操作，保留信息与编辑', (tester) async {
    await withDeviceMenu(tester, (fixture) async {
      await _rightClick(tester, deviceMenuOffline.displayName);
      final entries = tester.widgetList<PopupMenuItem<DeviceContextAction>>(
        find.byType(PopupMenuItem<DeviceContextAction>),
      );
      expect(
        entries.where((entry) => entry.enabled).map((entry) => entry.value),
        [DeviceContextAction.overview, DeviceContextAction.edit],
      );
      await _choose(tester, '截图', settle: false);
      expect(fixture.adb.captures, isEmpty);
    });
  });

  for (final removed in [false, true]) {
    testWidgets('菜单打开后设备${removed ? '删除' : '断线'}，不执行旧截图操作', (tester) async {
      await withDeviceMenu(tester, (fixture) async {
        await _rightClick(tester, deviceMenuTarget.displayName);
        if (removed) {
          fixture.registry.remove(deviceMenuTarget.id);
        } else {
          fixture.registry.disconnect(deviceMenuTarget.id);
        }
        await tester.pumpAndSettle();
        await _choose(tester, '截图', settle: false);
        expect(fixture.adb.captures, isEmpty);
        expect(fixture.host.savedFor, isEmpty);
      });
    });
  }

  testWidgets('截图请求未完成时显示进度且拦截重复右键', (tester) async {
    await withDeviceMenu(tester, (fixture) async {
      fixture.adb.gate = Completer<Uint8List>();
      await _rightClick(tester, deviceMenuTarget.displayName);
      // CircularProgressIndicator 持续动画，使用有限帧推进代替 pumpAndSettle。
      await tester.tap(
        find.widgetWithText(PopupMenuItem<DeviceContextAction>, '截图'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(
        find.text(deviceMenuAndroid.displayName).first,
        buttons: kSecondaryButton,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PopupMenuItem<DeviceContextAction>), findsNothing);
      fixture.adb.gate!.complete(deviceMenuImage);
      await fixture.waitForSavedScreenshot(tester);
      expect(fixture.adb.captures, [deviceMenuTarget.id]);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  testWidgets('截图失败反馈错误并释放操作状态', (tester) async {
    await withDeviceMenu(tester, (fixture) async {
      fixture.adb.fail = true;
      await _rightClick(tester, deviceMenuTarget.displayName);
      await _choose(tester, '截图', settle: false);
      expect(find.textContaining('capture failed'), findsOneWidget);
      expect(fixture.host.savedFor, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await _rightClick(tester, deviceMenuAndroid.displayName);
      expect(find.byType(PopupMenuItem<DeviceContextAction>), findsNWidgets(7));
    });
  });

  for (final entry in {
    '设备信息': 'overview',
    '应用': 'apps',
    '文件': 'files',
    '终端调试': 'terminal',
  }.entries) {
    testWidgets('${entry.key} 跳转携带右键设备及工具 Route', (tester) async {
      await withDeviceMenu(tester, (fixture) async {
        await _rightClick(tester, deviceMenuTarget.displayName);
        await _choose(tester, entry.key);
        expect(
          fixture.router.routeInformationProvider.value.uri.path,
          '/devices/${deviceMenuTarget.id}/${entry.value}',
        );
      });
    });
  }

  testWidgets('英文暗色菜单没有溢出，截图反馈使用本地化文案', (tester) async {
    await withDeviceMenu(
      tester,
      (fixture) async {
        await _rightClick(tester, deviceMenuTarget.displayName);
        expect(
          find.widgetWithText(PopupMenuItem<DeviceContextAction>, 'Screenshot'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(
            PopupMenuItem<DeviceContextAction>,
            'Edit Device Info',
          ),
          findsOneWidget,
        );
        await _choose(tester, 'Screenshot', settle: false);
        await fixture.waitForSavedScreenshot(tester);
        expect(find.textContaining('Saved successfully'), findsOneWidget);
        expect(find.textContaining('Copied to clipboard'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      language: 'en',
      brightness: Brightness.dark,
    );
  });

  testWidgets('纯 AirPlay 行仅提供投屏入口', (tester) async {
    await withDeviceMenu(
      tester,
      (fixture) async {
        await _rightClick(tester, 'AirPlay test');
        expect(find.byType(PopupMenuItem<DeviceContextAction>), findsOneWidget);
        expect(
          find.widgetWithText(PopupMenuItem<DeviceContextAction>, '投屏'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(PopupMenuItem<DeviceContextAction>, '截图'),
          findsNothing,
        );
      },
      devices: const [],
      airplay: const AirPlaySessionData(
        id: 1,
        serverName: 'AnyDeck',
        rtspPort: 0,
        videoPort: 0,
        status: AirPlayServerStatus.mirroring,
        clientName: 'AirPlay test',
      ),
    );
  });
}
