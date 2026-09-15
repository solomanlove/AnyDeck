import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ios/ios_ble_mouse_service.dart';

/// 一个纯 Dart 实现的高性能 MJPEG 图像流播放器。
/// 检索 JPEG 的起始标记 0xFF, 0xD8 (SOI) 与结束标记 0xFF, 0xD9 (EOI) 来分包渲染，
/// 无任何第三方系统或 C++ 编解码依赖，极度轻量且跨平台一致。
class IosMirrorViewer extends ConsumerStatefulWidget {
  const IosMirrorViewer({
    super.key,
    required this.deviceId,
    required this.port,
  });

  final String deviceId;
  final int port;

  @override
  ConsumerState<IosMirrorViewer> createState() => _IosMirrorViewerState();
}

class _IosMirrorViewerState extends ConsumerState<IosMirrorViewer> {
  Uint8List? _currentFrame;
  StreamSubscription<List<int>>? _subscription;
  HttpClient? _client;
  String? _errorMsg;
  int _retryCount = 0;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _startStreamConnection();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _closeConnection();
    super.dispose();
  }

  /// 停止流连接并释放所有网络资源。
  void _closeConnection() {
    _subscription?.cancel();
    _subscription = null;
    _client?.close(force: true);
    _client = null;
  }

  /// 开启 HTTP 连接并解析 MJPEG Multipart 流。
  Future<void> _startStreamConnection() async {
    _closeConnection();
    _client = HttpClient();
    
    // 设置连接超时时间为 3 秒
    _client!.connectionTimeout = const Duration(seconds: 3);
    
    final url = 'http://127.0.0.1:${widget.port}';
    debugPrint('[IosMirrorViewer] Connecting to stream url: $url');

    try {
      final request = await _client!.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw HttpException('HTTP status ${response.statusCode}');
      }

      if (mounted) {
        setState(() {
          _errorMsg = null;
          _retryCount = 0;
        });
      }

      final List<int> buffer = [];
      
      _subscription = response.listen(
        (chunk) {
          if (!mounted) return;
          buffer.addAll(chunk);
          
          while (true) {
            int soi = -1;
            // 搜索 JPEG 文件头 SOI (0xFF, 0xD8)
            for (int i = 0; i < buffer.length - 1; i++) {
              if (buffer[i] == 0xFF && buffer[i + 1] == 0xD8) {
                soi = i;
                break;
              }
            }

            if (soi == -1) {
              // 未找到 SOI，为防止内存暴涨且可能包含了半个 SOI 字节，保留最后一字节
              if (buffer.isNotEmpty) {
                final last = buffer.last;
                buffer.clear();
                buffer.add(last);
              }
              break;
            }

            // 搜索 JPEG 文件尾 EOI (0xFF, 0xD9)
            int eoi = -1;
            for (int i = soi + 2; i < buffer.length - 1; i++) {
              if (buffer[i] == 0xFF && buffer[i + 1] == 0xD9) {
                eoi = i + 2;
                break;
              }
            }

            if (eoi == -1) {
              // 找到了文件头但数据包未接收完毕，保留从 SOI 开始的内容并等待后续分片
              if (soi > 0) {
                final remaining = buffer.sublist(soi);
                buffer.clear();
                buffer.addAll(remaining);
              }
              break;
            }

            // 提取完整的 JPEG 字节数据
            final jpegFrame = Uint8List.fromList(buffer.sublist(soi, eoi));
            
            // 更新当前帧
            if (mounted) {
              setState(() {
                _currentFrame = jpegFrame;
              });
            }

            // 剔除已解析的帧数据并继续循环以处理多余缓冲
            final nextStart = eoi;
            if (nextStart < buffer.length) {
              final remaining = buffer.sublist(nextStart);
              buffer.clear();
              buffer.addAll(remaining);
            } else {
              buffer.clear();
              break;
            }
          }
        },
        onError: (err) {
          debugPrint('[IosMirrorViewer] Stream error: $err');
          _handleDisconnect(err.toString());
        },
        onDone: () {
          debugPrint('[IosMirrorViewer] Stream completed/closed');
          _handleDisconnect('Connection closed');
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[IosMirrorViewer] Connection failed: $e');
      _handleDisconnect(e.toString());
    }
  }

  /// 断开连接后的重试处理。
  void _handleDisconnect(String reason) {
    if (!mounted) return;
    
    setState(() {
      if (_currentFrame == null) {
        _errorMsg = '无法连接到视频流，请确认设备是否信任此电脑或重试。';
      }
    });

    _closeConnection();

    // 自动重试机制：前 5 次每隔 1 秒重试，之后每隔 3 秒重试
    if (_retryCount < 20) {
      _retryCount++;
      final delay = _retryCount < 5 ? const Duration(seconds: 1) : const Duration(seconds: 3);
      _retryTimer?.cancel();
      _retryTimer = Timer(delay, () {
        if (mounted) {
          _startStreamConnection();
        }
      });
    } else {
      if (mounted) {
        setState(() {
          _errorMsg = '连接超时，投屏初始化失败 ($reason)。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMsg != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMsg!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _errorMsg = null;
                    _retryCount = 0;
                  });
                  _startStreamConnection();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              )
            ],
          ),
        ),
      );
    }

    if (_currentFrame == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              '正在加载 iOS 投屏流画面...',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final bleMouseState = ref.watch(iosBleMouseProvider);
    final bleMouseNotifier = ref.read(iosBleMouseProvider.notifier);

    final imageWidget = Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: Image.memory(
        _currentFrame!,
        gaplessPlayback: true,
        fit: BoxFit.contain,
        alignment: Alignment.center,
      ),
    );

    return Stack(
      children: [
        if (bleMouseState.isEnabled)
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: bleMouseNotifier.handlePointerDown,
            onPointerMove: bleMouseNotifier.handlePointerMove,
            onPointerUp: bleMouseNotifier.handlePointerUp,
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                bleMouseNotifier.handlePointerScroll(event);
              }
            },
            child: imageWidget,
          )
        else
          imageWidget,
        if (bleMouseState.isEnabled)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: bleMouseState.state == BleMouseState.connected
                      ? Colors.greenAccent.withAlpha(180)
                      : Colors.orangeAccent.withAlpha(180),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bluetooth,
                    size: 14,
                    color: bleMouseState.state == BleMouseState.connected
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    bleMouseState.state == BleMouseState.connected
                        ? 'BLE 鼠标反控已就绪'
                        : 'BLE 鼠标等待配对...',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
