import 'package:flutter/services.dart';

class ScrcpyFlutter {
  static const MethodChannel _channel = MethodChannel('scrcpy_flutter');

  /// Starts mirroring for a given [deviceId] connecting to the server socket on [host]:[port].
  /// Returns the `textureId` used to display the stream with a [Texture] widget.
  static Future<int> startMirroring({
    required String deviceId,
    String host = '127.0.0.1',
    required int port,
  }) async {
    final int? textureId = await _channel.invokeMethod<int>('startMirroring', {
      'deviceId': deviceId,
      'host': host,
      'port': port,
    });
    if (textureId == null) {
      throw PlatformException(
        code: 'TEXTURE_REGISTRATION_FAILED',
        message: 'Could not register texture for device $deviceId',
      );
    }
    return textureId;
  }

  /// Stops mirroring and releases all resources for the given [deviceId].
  static Future<void> stopMirroring({required String deviceId}) async {
    await _channel.invokeMethod('stopMirroring', {
      'deviceId': deviceId,
    });
  }

  /// Returns the current decoded video stream width and height for a given [deviceId].
  static Future<Map<String, int>?> getVideoSize({required String deviceId}) async {
    final Map? size = await _channel.invokeMethod<Map>('getVideoSize', {
      'deviceId': deviceId,
    });
    if (size == null) return null;
    return {
      'width': size['width'] as int,
      'height': size['height'] as int,
    };
  }

  /// Sends a serialized control message (bytes) to the scrcpy server control socket.
  static Future<bool> sendControl({
    required String deviceId,
    required Uint8List controlMessage,
  }) async {
    final bool? success = await _channel.invokeMethod<bool>('sendControl', {
      'deviceId': deviceId,
      'controlMessage': controlMessage,
    });
    return success ?? false;
  }

  Future<String?> getPlatformVersion() => Future.value('42');
}
