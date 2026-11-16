import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../scrcpy/embedded_scrcpy_service.dart';
import '../scrcpy/screen_record_provider.dart';
import 'foldable_screen_models.dart';
import 'foldable_screen_service.dart';

export 'foldable_screen_models.dart';
export 'foldable_screen_session.dart' show FoldableScreenError;

/// 自动模式与当前屏幕分开保存；瞬时失败保留上一次确认的图标供重试。
class FoldableScreenUiState {
  const FoldableScreenUiState({
    this.snapshot,
    this.isBusy = false,
    this.error,
    this.mode = FoldableScreenMode.automatic,
  });

  final FoldableScreenSnapshot? snapshot;
  final bool isBusy;
  final FoldableScreenError? error;
  final FoldableScreenMode mode;
}

/// 每条投屏连接独立释放；设备侧文件锁负责跨 Isolate、跨 transport 排他。
final foldableScreenServiceProvider = Provider.autoDispose
    .family<FoldableScreenService, String>((ref, deviceId) {
      final service = FoldableScreenService(
        ref.watch(adbServiceProvider),
        deviceId,
      );
      ref.onDispose(() => unawaited(service.dispose()));
      return service;
    });

/// 仅支持设备开启低频状态查询，避免为普通手机常驻 ADB 轮询。
class FoldableScreenController extends Notifier<FoldableScreenUiState> {
  FoldableScreenController(this.deviceId);

  final String deviceId;
  late FoldableScreenService _service;
  Timer? _timer;
  int _generation = 0;
  Future<void>? _refreshing;

  @override
  FoldableScreenUiState build() {
    _service = ref.watch(foldableScreenServiceProvider(deviceId));
    ref.onDispose(() {
      ++_generation;
      _timer?.cancel();
    });
    ref.listen<int?>(activeEmbeddedMirrorProvider(deviceId), (previous, next) {
      if (previous != null && next == null) {
        ++_generation;
        _timer?.cancel();
        _timer = null;
        unawaited(_service.release().catchError((Object _) {}));
        state = const FoldableScreenUiState();
      } else if (previous == null && next != null) {
        unawaited(_resume());
      }
    });
    Future.microtask(() {
      if (ref.mounted) unawaited(refresh());
    });
    return const FoldableScreenUiState();
  }

  FoldableScreenMode _mode(FoldableScreenSnapshot? snapshot) {
    if (snapshot?.hasOverride != true || !_service.ownsOverride) {
      return FoldableScreenMode.automatic;
    }
    return snapshot!.currentScreen == FoldableScreen.inner
        ? FoldableScreenMode.inner
        : FoldableScreenMode.outer;
  }

  Future<void> _resume() async {
    await _refreshing;
    if (ref.mounted &&
        ref.read(activeEmbeddedMirrorProvider(deviceId)) != null) {
      await refresh();
    }
  }

  Future<void> refresh() {
    if (!ref.mounted || state.isBusy) return Future.value();
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    final generation = _generation;
    try {
      final snapshot = await _service.refresh();
      if (!ref.mounted || generation != _generation) return;
      state = FoldableScreenUiState(snapshot: snapshot, mode: _mode(snapshot));
      if (snapshot != null &&
          ref.read(activeEmbeddedMirrorProvider(deviceId)) != null) {
        _schedulePolling();
      } else {
        _timer?.cancel();
        _timer = null;
      }
    } catch (error) {
      if (ref.mounted && generation == _generation) {
        state = FoldableScreenUiState(
          snapshot: state.snapshot,
          mode: state.mode,
          error: _error(error),
        );
        if (ref.read(activeEmbeddedMirrorProvider(deviceId)) != null) {
          _schedulePolling();
        }
      }
    }
  }

  void _schedulePolling() {
    _timer ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(refresh()),
    );
  }

  FoldableScreenError? _guard() {
    if (ref.read(activeEmbeddedMirrorProvider(deviceId)) == null) {
      return FoldableScreenError.unavailable;
    }
    if (ref.read(screenPowerOffProvider(deviceId))) {
      return FoldableScreenError.screenOff;
    }
    final record = ref.read(screenRecordProvider(deviceId));
    if (record.isRecording || record.isStarting || record.isStopping) {
      return FoldableScreenError.recording;
    }
    return null;
  }

  Future<FoldableScreenError?> toggle() => _change(automatic: false);
  Future<FoldableScreenError?> restoreAutomatic() => _change(automatic: true);

  Future<FoldableScreenError?> _change({required bool automatic}) async {
    if (!ref.mounted || state.isBusy) return null;
    final blocked = _guard();
    if (blocked != null) return blocked;
    final generation = ++_generation;
    state = FoldableScreenUiState(
      snapshot: state.snapshot,
      mode: state.mode,
      isBusy: true,
    );
    try {
      // 点击时重新确认实际主屏，防止刚好手动折叠手机后反向选择错误。
      final current = await _service.refresh();
      if (!ref.mounted || generation != _generation) return null;
      if (current?.currentScreen == null) throw FoldableScreenError.unavailable;
      state = FoldableScreenUiState(
        snapshot: current,
        mode: _mode(current),
        isBusy: true,
      );
      final snapshot = automatic
          ? await _service.restoreAutomatic()
          : await _service.select(
              current!.currentScreen == FoldableScreen.inner
                  ? FoldableScreen.outer
                  : FoldableScreen.inner,
            );
      if (ref.mounted && generation == _generation) {
        state = FoldableScreenUiState(
          snapshot: snapshot,
          mode: _mode(snapshot),
        );
      }
      return null;
    } catch (error) {
      final failure = _error(error);
      if (ref.mounted && generation == _generation) {
        var snapshot = state.snapshot;
        if (failure == FoldableScreenError.unsupported) {
          snapshot = null;
          _timer?.cancel();
          _timer = null;
        } else {
          // 请求失败后的设备侧回滚可能改变了实际屏幕，不能继续显示旧的手动图标。
          try {
            snapshot = await _service.refresh(readDisplay: true);
          } catch (_) {}
        }
        if (!ref.mounted || generation != _generation) return failure;
        state = FoldableScreenUiState(
          snapshot: snapshot,
          mode: _mode(snapshot),
          error: failure,
        );
      }
      return failure;
    }
  }

  FoldableScreenError _error(Object error) => error is FoldableScreenError
      ? error
      : error is TimeoutException
      ? FoldableScreenError.timeout
      : FoldableScreenError.failed;
}

final foldableScreenProvider = NotifierProvider.autoDispose
    .family<FoldableScreenController, FoldableScreenUiState, String>(
      FoldableScreenController.new,
    );
