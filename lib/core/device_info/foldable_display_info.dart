/// 折叠机两块物理屏的分辨率摘要，随设备概览保存供离线查看。
class FoldableDisplayInfo {
  const FoldableDisplayInfo({
    required this.innerResolution,
    required this.outerResolution,
  });

  final String innerResolution;
  final String outerResolution;

  Map<String, dynamic> toJson() => {
    'innerResolution': innerResolution,
    'outerResolution': outerResolution,
  };

  /// 旧缓存或不完整的双屏信息不生成摘要，继续使用原来的单屏展示。
  static FoldableDisplayInfo? fromJson(Object? value) {
    if (value is! Map) return null;
    final inner = value['innerResolution'];
    final outer = value['outerResolution'];
    if (inner is! String || outer is! String) return null;
    if (inner.trim().isEmpty ||
        outer.trim().isEmpty ||
        inner == '-' ||
        outer == '-') {
      return null;
    }
    return FoldableDisplayInfo(innerResolution: inner, outerResolution: outer);
  }
}
