/// AirPlay 服务端运行状态枚举
enum AirPlayServerStatus {
  /// 待机等待连接中（Bonjour 广播已开启）
  idle,

  /// 正在接收投屏流并解码渲染中
  mirroring,

  /// 服务已停止
  stopped,

  /// 镜像流已建立，但尚未解码出画面；仍需打开手机镜像窗口。
  mirrorStarting;

  bool get isMirrorSession =>
      this == mirroring || this == mirrorStarting;

  static AirPlayServerStatus fromRaw(int value) => switch (value) {
        0 => idle,
        1 => mirroring,
        3 => mirrorStarting,
        _ => stopped,
      };
}

/// AirPlay 投屏会话数据模型
class AirPlaySessionData {
  const AirPlaySessionData({
    required this.id,
    required this.serverName,
    required this.rtspPort,
    required this.videoPort,
    required this.status,
    this.width = 0,
    this.height = 0,
    this.textureId,
    this.clientName,
    this.clientDeviceId,
    this.clientModel,
    this.additionalSessions = const [],
    this.isVideoPlaying = false,
  });

  /// 会话唯一标识句柄
  final int id;

  /// 在 iPhone 屏幕镜像列表中展示的广播名称
  final String serverName;

  /// RTSP 信令端口
  final int rtspPort;

  /// 视频流接收端口
  final int videoPort;

  /// 当前状态
  final AirPlayServerStatus status;

  /// 投屏视频宽度
  final int width;

  /// 投屏视频高度
  final int height;

  /// Flutter 外部纹理 ID (若已注册)
  final int? textureId;

  /// 连接的客户端设备名 (例如 "iPhone")
  final String? clientName;

  /// 连接的客户端硬件标识 (例如 AirPlay SETUP 上报的 deviceID / MAC)
  final String? clientDeviceId;

  /// 连接的客户端机型标识 (例如 "iPhone10,3")
  final String? clientModel;

  /// 多设备并发投屏时的附加 AirPlay 会话列表
  final List<AirPlaySessionData> additionalSessions;

  /// HTTP 视频播放器会话，与手机镜像状态独立。
  final bool isVideoPlaying;

  /// 当前汇总的所有 AirPlay 会话实例（含主会话与并发附加会话）
  List<AirPlaySessionData> get allSessions => [this, ...additionalSessions];

  /// 当前镜像会话（含已建立、等待首帧的会话），不包含 HTTP 视频
  List<AirPlaySessionData> get mirroringSessions => allSessions
      .where((session) => session.status.isMirrorSession)
      .toList();

  /// 是否存在任一正在投屏的会话
  bool get hasAnyMirroring =>
      allSessions.any((s) => s.status.isMirrorSession);

  /// 是否存在任一处于待机广播中的会话
  bool get hasAnyBroadcasting =>
      allSessions.any((s) => s.status == AirPlayServerStatus.idle);

  AirPlaySessionData copyWith({
    AirPlayServerStatus? status,
    int? width,
    int? height,
    int? textureId,
    String? clientName,
    String? clientDeviceId,
    String? clientModel,
    bool clearClient = false,
    List<AirPlaySessionData>? additionalSessions,
    bool? isVideoPlaying,
  }) {
    return AirPlaySessionData(
      id: id,
      isVideoPlaying: isVideoPlaying ?? this.isVideoPlaying,
      serverName: serverName,
      rtspPort: rtspPort,
      videoPort: videoPort,
      status: status ?? this.status,
      width: width ?? this.width,
      height: height ?? this.height,
      textureId: textureId ?? this.textureId,
      clientName: clearClient ? null : (clientName ?? this.clientName),
      clientDeviceId:
          clearClient ? null : (clientDeviceId ?? this.clientDeviceId),
      clientModel: clearClient ? null : (clientModel ?? this.clientModel),
      additionalSessions: additionalSessions ?? this.additionalSessions,
    );
  }
}
