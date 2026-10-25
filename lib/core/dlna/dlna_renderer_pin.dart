part of 'dlna_renderer_service.dart';

/// 把主窗口语言的图钉文案同步给两种 DLNA 播放窗口。
extension DlnaRendererPin on DlnaRendererService {
  Future<void> setPinLabels(String pin, String unpin) async {
    final labels = {'pin': pin, 'unpin': unpin};
    await DlnaRendererService._player.invokeMethod<void>(
      'setPinLabels',
      labels,
    );
    await _fallback.setPinLabels(pin, unpin);
  }
}
