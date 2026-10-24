import 'dart:async';

import 'package:flutter/foundation.dart';

/// 投屏剪贴板双向同步状态；只同步文本变化，避免回写形成循环。
///
/// [readHost] / [writeHost] 读写电脑剪贴板，[writeDevice] 通过投屏 control
/// socket 写入手机剪贴板；关闭面板时调用 [dispose] 停止轮询。
class MirrorClipboardSyncController extends ChangeNotifier {
  MirrorClipboardSyncController({
    required this.readHost,
    required this.writeHost,
    required this.writeDevice,
  });

  final Future<String?> Function() readHost;
  final Future<void> Function(String) writeHost;
  final Future<bool> Function(String, {required bool paste}) writeDevice;

  String? hostText;
  String? deviceText;
  String? errorKey;
  bool autoSync = true;
  bool sendingDevice = false;
  bool copyingHost = false;

  Timer? _timer;
  bool _disposed = false;
  bool _polling = false;
  String? _sentDeviceText;
  String? _pendingHostText;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// 记录打开面板时的电脑内容；只同步此后的内容变化。
  Future<void> start() async {
    try {
      hostText = await readHost();
      _changed();
    } catch (_) {
      errorKey = 'mirrorClipboardReadFailed';
      _changed();
    }
    if (_disposed) return;
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(pollHost()),
    );
  }

  /// 轮询系统剪贴板只读取文本，不保留历史，也不重复发送相同内容。
  Future<void> pollHost() async {
    if (_disposed || _polling || sendingDevice || copyingHost) return;
    _polling = true;
    try {
      final text = await readHost();
      if (_disposed || text == hostText) return;
      hostText = text;
      errorKey = null;
      _changed();
      if (autoSync && text != null && text.isNotEmpty) {
        await _sendDevice(text, paste: false);
      }
    } catch (_) {
      if (!_disposed) {
        errorKey = 'mirrorClipboardReadFailed';
        _changed();
      }
    } finally {
      _polling = false;
    }
  }

  /// 手机首次返回的文本也参与同步，确保空剪贴板后的第一次复制不丢失。
  void onDeviceText(String text) {
    if (_disposed || text == deviceText) return;
    deviceText = text;
    _changed();
    if (text == _sentDeviceText) return;
    _sentDeviceText = null;
    if (autoSync && text.isNotEmpty && text != hostText) {
      unawaited(_copyHost(text));
    }
  }

  void setAutoSync(bool enabled) {
    autoSync = enabled;
    if (!enabled) _pendingHostText = null;
    _changed();
  }

  /// 将电脑文本放入手机剪贴板并请求粘贴到当前焦点输入框。
  Future<bool> pasteToDevice() async {
    final text = hostText;
    if (text == null || text.isEmpty) return false;
    return _sendDevice(text, paste: true);
  }

  /// 将手机最近收到的文本复制到电脑剪贴板。
  Future<bool> copyToHost() async {
    final text = deviceText;
    if (text == null || text.isEmpty) return false;
    return _copyHost(text);
  }

  Future<bool> _sendDevice(String text, {required bool paste}) async {
    if (_disposed || sendingDevice) return false;
    sendingDevice = true;
    _changed();
    try {
      final success = await writeDevice(text, paste: paste);
      if (!_disposed) {
        errorKey = success ? null : 'mirrorClipboardSendFailed';
        if (success) _sentDeviceText = text;
        _changed();
      }
      return success;
    } catch (error) {
      if (!_disposed) {
        errorKey = error is ArgumentError
            ? 'mirrorClipboardTooLarge'
            : 'mirrorClipboardSendFailed';
        _changed();
      }
      return false;
    } finally {
      sendingDevice = false;
      _changed();
    }
  }

  Future<bool> _copyHost(String text) async {
    if (_disposed) return false;
    if (copyingHost) {
      _pendingHostText = text;
      return true;
    }
    copyingHost = true;
    _changed();
    try {
      await writeHost(text);
      if (!_disposed) {
        hostText = text;
        errorKey = null;
        _changed();
      }
      return true;
    } catch (_) {
      if (!_disposed) {
        errorKey = 'mirrorClipboardCopyFailed';
        _changed();
      }
      return false;
    } finally {
      copyingHost = false;
      final pending = _pendingHostText;
      _pendingHostText = null;
      _changed();
      if (!_disposed && autoSync && pending != null && pending != hostText) {
        unawaited(_copyHost(pending));
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
