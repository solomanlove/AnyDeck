import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_flutter/scrcpy_flutter.dart';
import 'package:scrcpy_flutter/scrcpy_flutter_platform_interface.dart';
import 'package:scrcpy_flutter/scrcpy_flutter_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockScrcpyFlutterPlatform
    with MockPlatformInterfaceMixin
    implements ScrcpyFlutterPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final ScrcpyFlutterPlatform initialPlatform = ScrcpyFlutterPlatform.instance;

  test('$MethodChannelScrcpyFlutter is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelScrcpyFlutter>());
  });

  test('getPlatformVersion', () async {
    ScrcpyFlutter scrcpyFlutterPlugin = ScrcpyFlutter();
    MockScrcpyFlutterPlatform fakePlatform = MockScrcpyFlutterPlatform();
    ScrcpyFlutterPlatform.instance = fakePlatform;

    expect(await scrcpyFlutterPlugin.getPlatformVersion(), '42');
  });
}
