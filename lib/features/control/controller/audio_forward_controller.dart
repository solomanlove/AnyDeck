import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/auxiliary_backend.dart';
import '../../../core/scrcpy/device_capture_compatibility.dart';

/// 纯音频转发（无画面）状态模型
class AudioForwardState {
  /// 创建纯音频转发状态模型
  const AudioForwardState({
    this.isActive = false,
    this.isStarting = false,
    this.isStopping = false,
    this.errorMessage,
  });

  /// 是否正在转发音频
  final bool isActive;

  /// 是否正在启动过程中
  final bool isStarting;

  /// 是否正在停止并释放后台音频 Session。
  final bool isStopping;

  /// 错误信息（如有）
  final String? errorMessage;

  /// 复制并更新部分属性
  AudioForwardState copyWith({
    bool? isActive,
    bool? isStarting,
    bool? isStopping,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AudioForwardState(
      isActive: isActive ?? this.isActive,
      isStarting: isStarting ?? this.isStarting,
      isStopping: isStopping ?? this.isStopping,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// 针对单台设备纯音频转发的状态控制器 Provider (按 deviceId 隔离)
final audioForwardControllerProvider =
    NotifierProvider.family<AudioForwardController, AudioForwardState, String>(
      AudioForwardController.new,
    );

/// 纯音频转发业务控制器，负责管理 Rust 后台音频 Session 生命周期。
class AudioForwardController extends Notifier<AudioForwardState> {
  /// 创建纯音频控制器实例，绑定目标设备 ID
  AudioForwardController(this.deviceId);

  /// 目标 ADB 设备 ID / 序列号
  final String deviceId;
  AuxiliaryBackend? _backend;

  @override
  AudioForwardState build() {
    // 监听设备在线状态：如果设备离线且正在运行，则自动停止并回收资源
    ref.listen(deviceOnlineProvider(deviceId), (_, isOnline) {
      if (!isOnline && (state.isActive || _backend != null)) {
        stop();
      }
    });

    // 页面/Provider 销毁时清理后台 Session，防止设备端残留服务。
    ref.onDispose(() {
      final backend = _backend;
      _backend = null;
      backend?.cancel();
      if (backend != null) unawaited(backend.stop());
    });

    return const AudioForwardState();
  }

  /// 启动纯音频转发（无画面）
  /// 返回是否启动成功
  Future<bool> start() async {
    if (state.isStarting || state.isStopping || state.isActive) return false;

    // 1. 检查设备是否在线
    final isOnline = ref.read(deviceOnlineProvider(deviceId));
    if (!isOnline) {
      state = state.copyWith(errorMessage: 'offline');
      return false;
    }

    // 2. 检查 Android SDK 版本（Android 11+ / API 30+ 原生支持音频转发）
    final sdk = await ref.read(captureSdkProvider(deviceId).future);
    if (sdk != null && sdk > 0 && sdk < 30) {
      state = state.copyWith(errorMessage: 'unsupported');
      return false;
    }

    state = state.copyWith(isStarting: true, clearError: true);

    try {
      final adb = ref.read(adbServiceProvider);
      // 若设备处于休眠或息屏状态，发送唤醒键确保音频系统正常产出
      unawaited(adb.shellArgs(deviceId, ['input', 'keyevent', '224']));

      // 启动内置 Rust 纯音频 Session，不创建视频 Texture 或独立窗口。
      final backend = ref.read(audioPlaybackBackendFactoryProvider)(deviceId);
      _backend = backend;
      await backend.start();
      unawaited(
        backend.exited.then((_) {
          if (ref.mounted && identical(_backend, backend)) {
            _backend = null;
            state = const AudioForwardState();
          }
        }),
      );

      state = state.copyWith(isActive: true, isStarting: false);
      return true;
    } catch (e) {
      final backend = _backend;
      _backend = null;
      backend?.cancel();
      if (backend != null) unawaited(backend.stop());
      if (ref.mounted) {
        state = state.copyWith(
          isActive: false,
          isStarting: false,
          errorMessage: e.toString(),
        );
      }
      return false;
    }
  }

  /// 停止纯音频转发
  Future<void> stop() async {
    if (state.isStopping) return;
    final backend = _backend;
    _backend = null;
    state = state.copyWith(isStopping: true);
    try {
      if (backend != null) await backend.stop();
    } finally {
      if (ref.mounted) state = const AudioForwardState();
    }
  }

  /// 切换纯音频转发开关
  Future<bool> toggle() async {
    if (state.isActive) {
      await stop();
      return false;
    } else {
      return await start();
    }
  }
}
