import 'android_display_parser.dart';
import 'foldable_display_info.dart';

/// 从系统快照识别折叠机的内外屏；不依赖机型表、屏幕开关状态或逻辑 ID。
class FoldableDisplayParser {
  static final _deviceInfo = RegExp(
    r'^\s*DisplayDeviceInfo\{[^\r\n]*',
    multiLine: true,
  );
  static final _internal = RegExp(r'\btype\s+(?:INTERNAL|BUILT_IN)\b');
  static final _identity = RegExp(
    r'DisplayDeviceInfo\{"([^"]+)":\s*uniqueId="local:(\d+)"',
  );
  static final _size = RegExp(r'",\s*(\d+)\s*x\s*(\d+)\s*,');
  static final _mode = RegExp(r'\bid=\d+,\s*width=(\d+),\s*height=(\d+)');
  static final _dpi = RegExp(r',\s*([\d.]+)\s*x\s*([\d.]+)\s*dpi\b');

  /// 必须有两块完整的内置物理屏及折叠特征；虚拟屏与外接屏不参与判断。
  static FoldableDisplayInfo? parse(
    String displayDump, {
    Map<String, String> properties = const {},
    String deviceStates = '',
  }) {
    final panels = <String, _PhysicalPanel?>{};
    for (final match in _deviceInfo.allMatches(displayDump)) {
      final info = match.group(0)!;
      if (!_internal.hasMatch(info)) continue;
      final identity = _identity.firstMatch(info);
      if (identity == null) continue;
      panels.putIfAbsent(
        identity.group(2)!,
        () => _parsePanel(identity.group(1)!, info),
      );
    }
    if (panels.length != 2 || panels.values.any((panel) => panel == null)) {
      return null;
    }
    final pair = panels.values.cast<_PhysicalPanel>().toList(growable: false);
    final namedInner = pair.where((panel) => panel.isInner).toList();
    final namedOuter = pair.where((panel) => panel.isOuter).toList();
    if (namedInner.length == 1 &&
        namedOuter.length == 1 &&
        namedInner.single != namedOuter.single) {
      return _summary(namedInner.single, namedOuter.single);
    }
    if (!_hasFoldableSignal(properties, deviceStates)) return null;

    // 厂商常将两屏都命名为“内置屏幕”。已确认折叠设备后，优先按物理面积
    // 区分内外屏；缺少真实 DPI 时使用最大像素面积。相近尺寸不强行标注。
    final physicalAreas = pair.every((panel) => panel.physicalArea != null);
    final firstArea = physicalAreas ? pair[0].physicalArea! : pair[0].pixelArea;
    final secondArea = physicalAreas
        ? pair[1].physicalArea!
        : pair[1].pixelArea;
    if (firstArea > secondArea * 1.1) return _summary(pair[0], pair[1]);
    if (secondArea > firstArea * 1.1) return _summary(pair[1], pair[0]);
    return null;
  }

  static FoldableDisplayInfo _summary(
    _PhysicalPanel inner,
    _PhysicalPanel outer,
  ) {
    return FoldableDisplayInfo(
      innerResolution: AndroidDisplayParser.formatResolution(inner.size),
      outerResolution: AndroidDisplayParser.formatResolution(outer.size),
    );
  }

  static bool _hasFoldableSignal(
    Map<String, String> properties,
    String states,
  ) {
    final supportFold = properties['ro.vendor.display.supportfold']?.trim();
    if (supportFold == '1' || supportFold == 'true') return true;
    final foldDisplay = properties['ro.config.fold_disp']?.split(',');
    if (foldDisplay != null &&
        foldDisplay.length >= 6 &&
        foldDisplay.every((value) => int.tryParse(value.trim()) != null) &&
        foldDisplay.where((value) => int.parse(value.trim()) > 0).length >= 3) {
      return true;
    }
    // 使用状态名称而非固定编号，兼容 Honor、Samsung 与 AOSP 的编号差异。
    final closed = RegExp(
      r'\b(?:STATE_)?(?:CLOSED|FOLDED)\b',
      caseSensitive: false,
    ).hasMatch(states);
    final opened = RegExp(
      r'\b(?:STATE_)?(?:OPEN|OPENED|UNFOLDED|FLAT|HALF_OPEN|HALF_OPENED)\b',
      caseSensitive: false,
    ).hasMatch(states);
    return closed && opened;
  }

  static _PhysicalPanel? _parsePanel(String name, String info) {
    final size = _size.firstMatch(info);
    if (size == null) return null;
    final width = int.tryParse(size.group(1)!);
    final height = int.tryParse(size.group(2)!);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    var nativeWidth = width;
    var nativeHeight = height;
    // 多个刷新率或缩放模式属于同一块屏；选择最大支持尺寸作为物理分辨率。
    for (final mode in _mode.allMatches(info)) {
      final modeWidth = int.tryParse(mode.group(1)!) ?? 0;
      final modeHeight = int.tryParse(mode.group(2)!) ?? 0;
      if (modeWidth * modeHeight > nativeWidth * nativeHeight) {
        nativeWidth = modeWidth;
        nativeHeight = modeHeight;
      }
    }
    final dpi = _dpi.firstMatch(info);
    final xDpi = double.tryParse(dpi?.group(1) ?? '') ?? 0;
    final yDpi = double.tryParse(dpi?.group(2) ?? '') ?? 0;
    final physicalArea = xDpi > 0 && yDpi > 0 && xDpi.isFinite && yDpi.isFinite
        ? width / xDpi * height / yDpi
        : null;
    return _PhysicalPanel(
      name: name,
      width: nativeWidth,
      height: nativeHeight,
      physicalArea: physicalArea,
    );
  }
}

/// 单块内置屏的解析中间值，不持久化设备 ID 和系统原始输出。
class _PhysicalPanel {
  const _PhysicalPanel({
    required this.name,
    required this.width,
    required this.height,
    required this.physicalArea,
  });

  final String name;
  final int width;
  final int height;
  final double? physicalArea;

  String get size => '${width}x$height';
  int get pixelArea => width * height;
  bool get isInner =>
      RegExp(r'\binner\b|内屏|內屏', caseSensitive: false).hasMatch(name);
  bool get isOuter =>
      RegExp(r'\b(?:outer|cover)\b|外屏', caseSensitive: false).hasMatch(name);
}
