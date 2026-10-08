/// AirPlay 服务端运行状态枚举
enum AirPlayServerStatus {
  /// 待机等待连接中（Bonjour 广播已开启）
  idle,

  /// 正在接收投屏流并解码渲染中
  mirroring,

  /// 服务已停止
  stopped;

  static AirPlayServerStatus fromRaw(int value) => switch (value) {
        0 => idle,
        1 => mirroring,
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

  AirPlaySessionData copyWith({
    AirPlayServerStatus? status,
    int? width,
    int? height,
    int? textureId,
    String? clientName,
  }) {
    return AirPlaySessionData(
      id: id,
      serverName: serverName,
      rtspPort: rtspPort,
      videoPort: videoPort,
      status: status ?? this.status,
      width: width ?? this.width,
      height: height ?? this.height,
      textureId: textureId ?? this.textureId,
      clientName: clientName ?? this.clientName,
    );
  }
}
