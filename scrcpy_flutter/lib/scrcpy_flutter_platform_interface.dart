import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'scrcpy_flutter_method_channel.dart';

abstract class ScrcpyFlutterPlatform extends PlatformInterface {
  /// Constructs a ScrcpyFlutterPlatform.
  ScrcpyFlutterPlatform() : super(token: _token);

  static final Object _token = Object();

  static ScrcpyFlutterPlatform _instance = MethodChannelScrcpyFlutter();

  /// The default instance of [ScrcpyFlutterPlatform] to use.
  ///
  /// Defaults to [MethodChannelScrcpyFlutter].
  static ScrcpyFlutterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ScrcpyFlutterPlatform] when
  /// they register themselves.
  static set instance(ScrcpyFlutterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
