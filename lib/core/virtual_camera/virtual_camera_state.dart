/// macOS 原生虚拟摄像头快照；不携带帧数据，页面关闭后采集由原生服务管理。
class VirtualCameraState {
  const VirtualCameraState({
    this.supported = false,
    this.installed = false,
    this.activation = 'notInstalled',
    this.enabled = false,
    this.deviceId,
    this.front = false,
    this.streaming = false,
    this.clients = 0,
    this.frames = 0,
    this.error,
    this.busy = false,
  });

  factory VirtualCameraState.fromMap(Map<Object?, Object?> map) =>
      VirtualCameraState(
        supported: map['supported'] == true,
        installed: map['installed'] == true,
        activation: map['activation'] is String
            ? map['activation']! as String
            : 'notInstalled',
        enabled: map['enabled'] == true,
        deviceId: map['deviceId'] is String ? map['deviceId']! as String : null,
        front: map['front'] == true,
        streaming: map['streaming'] == true,
        clients: map['clients'] is num ? (map['clients']! as num).toInt() : 0,
        frames: map['frames'] is num ? (map['frames']! as num).toInt() : 0,
        error: map['error'] is String && (map['error']! as String).isNotEmpty
            ? map['error']! as String
            : null,
      );

  final bool supported;
  final bool installed;
  final String activation;
  final bool enabled;
  final String? deviceId;
  final bool front;
  final bool streaming;
  final int clients;
  final int frames;
  final String? error;
  final bool busy;

  bool get ready => supported && installed && activation == 'ready';
  bool ownsDevice(String id) => enabled && deviceId == id;

  VirtualCameraState withOperation({bool busy = false, String? error}) =>
      VirtualCameraState(
        supported: supported,
        installed: installed,
        activation: activation,
        enabled: enabled,
        deviceId: deviceId,
        front: front,
        streaming: streaming,
        clients: clients,
        frames: frames,
        error: error,
        busy: busy,
      );

  /// 原生错误仅映射为已登记的文案，避免向用户展示内部路径和底层异常。
  String get messageKey {
    if (error != null) {
      return switch (error) {
        'applicationsRequired' || 'virtualCameraApplicationsRequired' =>
          'virtualCameraApplicationsRequired',
        'signingRequired' ||
        'virtualCameraSigningRequired' => 'virtualCameraSigningRequired',
        'cameraUnavailable' ||
        'cameraStartFailed' => 'virtualCameraSourceFailed',
        'deviceDisconnected' ||
        'cameraDisconnected' => 'virtualCameraDisconnected',
        'unsupported' => 'virtualCameraUnsupported',
        'virtualCameraPreviewBlocked' => 'virtualCameraPreviewBlocked',
        _ => 'virtualCameraFailed',
      };
    }
    if (!supported) return 'virtualCameraUnsupported';
    if (activation == 'needsApproval') return 'virtualCameraNeedsApproval';
    if (activation == 'needsReboot') return 'virtualCameraNeedsReboot';
    if (!installed) return 'virtualCameraNotInstalled';
    if (streaming) return 'virtualCameraStreaming';
    if (enabled && clients > 0) return 'virtualCameraStarting';
    if (enabled) return 'virtualCameraWaiting';
    return 'virtualCameraReady';
  }
}
