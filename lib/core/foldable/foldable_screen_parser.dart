import 'foldable_screen_models.dart';

/// 从运行时状态与物理屏布局确认切屏能力，不使用厂商或固定编号猜测。
class FoldableScreenParser {
  static final _state = RegExp(
    r"DeviceState\{\s*identifier=(\d+),\s*name='([^']+)'[^}]*\}",
  );
  static final _deviceInfo = RegExp(
    r'^\s*DisplayDeviceInfo\{[^\r\n]*',
    multiLine: true,
  );
  static final _physicalIdentity = RegExp(
    r'DisplayDeviceInfo\{"([^"]+)":\s*uniqueId="local:(\d+)"',
  );
  static final _internal = RegExp(r'\btype\s+(?:INTERNAL|BUILT_IN)\b');
  static final _size = RegExp(r'",\s*(\d+)\s*x\s*(\d+)\s*,');
  static final _layoutLine = RegExp(
    r'^\s*state\((-?\d+)\):\s*([^\r\n]+)',
    multiLine: true,
  );
  static final _layoutDisplay = RegExp(
    r'\{\s*dispId:\s*(\d+)\((ON|OFF)\)[^{}]*?\baddr:\s*'
    r'StablePhysical\{\s*id=(\d+),[^}]*\}[^{}]*\}',
  );

  /// 只接受两块真实内置屏和普通内外屏姿态的完整双向映射。
  /// stateDump 支持完整 dumpsys 与低成本的 cmd device_state state 输出。
  static FoldableScreenSnapshot? parse({
    required String states,
    required String stateDump,
    required String displayDump,
  }) {
    final supported = <int, String>{};
    for (final match in _state.allMatches(states)) {
      final id = int.tryParse(match.group(1)!);
      if (id == null) return null;
      final name = match.group(2)!;
      if (supported.containsKey(id) && supported[id] != name) return null;
      supported[id] = name;
    }
    if (supported.isEmpty) return null;
    final panels = _panels(displayDump);
    if (panels == null) return null;
    final layouts = _layouts(displayDump);
    if (layouts == null) return null;
    final inner = _target(supported, layouts, panels, FoldableScreen.inner);
    final outer = _target(supported, layouts, panels, FoldableScreen.outer);
    if (inner == null ||
        outer == null ||
        inner.physicalId == outer.physicalId) {
      return null;
    }
    if (!_matchesRole(panels[inner.physicalId]!, FoldableScreen.inner) ||
        !_matchesRole(panels[outer.physicalId]!, FoldableScreen.outer)) {
      return null;
    }
    final current = _currentState(stateDump);
    if (current == null || !supported.containsKey(current.committedId)) {
      return null;
    }
    final primary = layouts[current.committedId]?[0];
    final physicalId = primary?.enabled == true ? primary?.physicalId : null;
    final currentScreen = physicalId == inner.physicalId
        ? FoldableScreen.inner
        : physicalId == outer.physicalId
        ? FoldableScreen.outer
        : null;
    return FoldableScreenSnapshot(
      capability: FoldableScreenCapability(
        innerStateId: inner.stateId,
        outerStateId: outer.stateId,
        innerPhysicalId: inner.physicalId,
        outerPhysicalId: outer.physicalId,
      ),
      currentScreen: currentScreen,
      committedStateId: current.committedId,
      overrideStateId: current.overrideId,
      hasOverride: current.overrideId != null,
    );
  }

  static Map<String, String>? _panels(String dump) {
    final panels = <String, String>{};
    for (final match in _deviceInfo.allMatches(dump)) {
      final info = match.group(0)!;
      if (!_internal.hasMatch(info)) continue;
      final identity = _physicalIdentity.firstMatch(info);
      if (identity == null) {
        if (info.contains('uniqueId="virtual:')) continue;
        return null;
      }
      final size = _size.firstMatch(info);
      if (size == null ||
          (int.tryParse(size.group(1)!) ?? 0) <= 0 ||
          (int.tryParse(size.group(2)!) ?? 0) <= 0) {
        return null;
      }
      final id = identity.group(2)!;
      final name = identity.group(1)!;
      if (panels.containsKey(id) && panels[id] != name) return null;
      panels[id] = name;
    }
    return panels.length == 2 ? panels : null;
  }

  static Map<int, Map<int, _LayoutDisplay>>? _layouts(String dump) {
    final start = dump.indexOf('DeviceStateToLayoutMap:');
    if (start < 0) return null;
    final section = dump.substring(start).split(RegExp(r'\r?\n(?=\S)')).first;
    final layouts = <int, Map<int, _LayoutDisplay>>{};
    for (final match in _layoutLine.allMatches(section)) {
      final id = int.tryParse(match.group(1)!);
      if (id == null) return null;
      final displays = <int, _LayoutDisplay>{};
      final body = match.group(2)!;
      final entries = _layoutDisplay.allMatches(body).toList(growable: false);
      if (entries.length != RegExp(r'\bdispId:').allMatches(body).length) {
        return null;
      }
      for (final entry in entries) {
        final displayId = int.tryParse(entry.group(1)!);
        if (displayId == null || displays.containsKey(displayId)) return null;
        displays[displayId] = _LayoutDisplay(
          entry.group(3)!,
          entry.group(2) == 'ON',
        );
      }
      if (layouts.containsKey(id)) return null;
      layouts[id] = displays;
    }
    return layouts.isEmpty ? null : layouts;
  }

  static _Target? _target(
    Map<int, String> states,
    Map<int, Map<int, _LayoutDisplay>> layouts,
    Map<String, String> panels,
    FoldableScreen screen,
  ) {
    _Target? target;
    for (final state in states.entries) {
      // 严格白名单排除 HALF、TENT、REAR、CONCURRENT 等特殊姿态。
      final name = state.value.toUpperCase().replaceFirst(
        RegExp(r'^STATE_'),
        '',
      );
      final names = screen == FoldableScreen.inner
          ? const {'OPEN', 'OPENED', 'UNFOLDED', 'FLAT'}
          : const {'CLOSE', 'CLOSED', 'FOLDED'};
      if (!names.contains(name)) continue;
      final layout = layouts[state.key];
      if (layout == null || layout.length != 2) continue;
      final primary = layout[0];
      if (primary == null || !primary.enabled) continue;
      final physicalIds = layout.values
          .map((value) => value.physicalId)
          .toSet();
      if (physicalIds.length != 2 ||
          !physicalIds.containsAll(panels.keys) ||
          layout.values.where((value) => value.enabled).length != 1) {
        continue;
      }
      if (target != null && target.physicalId != primary.physicalId) {
        return null;
      }
      target ??= _Target(state.key, primary.physicalId);
    }
    return target;
  }

  static bool _matchesRole(String name, FoldableScreen screen) {
    final inner = RegExp(
      r'\binner\b|内屏|內屏',
      caseSensitive: false,
    ).hasMatch(name);
    final outer = RegExp(
      r'\b(?:outer|cover)\b|外屏',
      caseSensitive: false,
    ).hasMatch(name);
    return screen == FoldableScreen.inner ? !outer : !inner;
  }

  static _CurrentState? _currentState(String dump) {
    final full = dump.contains('mCommittedState=');
    final committedLine = RegExp(
      full ? r'mCommittedState=([^\r\n]+)' : r'Committed state:\s*([^\r\n]+)',
    ).firstMatch(dump)?.group(1);
    final committed = _state.firstMatch(committedLine ?? '');
    if (committed == null) return null;
    final committedId = int.tryParse(committed.group(1)!);
    if (committedId == null) return null;
    final overrideLine = RegExp(
      full ? r'mOverrideState=([^\r\n]+)' : r'Override state:\s*([^\r\n]+)',
    ).firstMatch(dump)?.group(1);
    if (full && overrideLine == null) return null;
    if (overrideLine == null || overrideLine.trim() == 'Optional.empty') {
      return _CurrentState(committedId, null);
    }
    final override = _state.firstMatch(overrideLine);
    final overrideId = int.tryParse(override?.group(1) ?? '');
    return overrideId == null ? null : _CurrentState(committedId, overrideId);
  }
}

/// 只保留布局选择所需字段，避免持有包含应用等信息的系统原文。
class _LayoutDisplay {
  const _LayoutDisplay(this.physicalId, this.enabled);

  final String physicalId;
  final bool enabled;
}

/// 一种普通姿态经过布局校验后的主屏目标。
class _Target {
  const _Target(this.stateId, this.physicalId);

  final int stateId;
  final String physicalId;
}

/// 已提交状态与覆盖状态的解析中间值。
class _CurrentState {
  const _CurrentState(this.committedId, this.overrideId);

  final int committedId;
  final int? overrideId;
}
