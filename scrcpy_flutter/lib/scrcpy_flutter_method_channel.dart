import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'scrcpy_flutter_platform_interface.dart';

/// An implementation of [ScrcpyFlutterPlatform] that uses method channels.
class MethodChannelScrcpyFlutter extends ScrcpyFlutterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('scrcpy_flutter');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
