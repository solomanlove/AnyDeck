/// 网页调试使用的已连接设备 Web 目标元数据。
class WebpageTarget {
  const WebpageTarget({
    required this.id,
    required this.title,
    required this.url,
    required this.type,
    required this.packageName,
    required this.pid,
    required this.socketName,
    required this.devtoolsFrontendUrl,
    required this.webSocketDebuggerUrl,
    required this.port,
  });

  /// 目标唯一 ID
  final String id;

  /// 网页标题
  final String title;

  /// 网页 URL
  final String url;

  /// 目标类型（如 page、webview 等）
  final String type;

  /// 应用包名
  final String packageName;

  /// 进程 PID
  final String pid;

  /// Sockets 抽象名称（不含 @）
  final String socketName;

  /// Google 托管的 DevTools 前端 URL
  final String devtoolsFrontendUrl;

  /// WebSocket 调试端点 URL
  final String webSocketDebuggerUrl;

  /// 转发到的本地 TCP 端口
  final int port;

  factory WebpageTarget.fromJson({
    required Map<String, dynamic> json,
    required String packageName,
    required String pid,
    required String socketName,
    required int port,
  }) {
    return WebpageTarget(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      type: json['type'] as String? ?? '',
      packageName: packageName,
      pid: pid,
      socketName: socketName,
      devtoolsFrontendUrl: json['devtoolsFrontendUrl'] as String? ?? '',
      webSocketDebuggerUrl: json['webSocketDebuggerUrl'] as String? ?? '',
      port: port,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'url': url,
      'type': type,
      'packageName': packageName,
      'pid': pid,
      'socketName': socketName,
      'devtoolsFrontendUrl': devtoolsFrontendUrl,
      'webSocketDebuggerUrl': webSocketDebuggerUrl,
      'port': port,
    };
  }
}
