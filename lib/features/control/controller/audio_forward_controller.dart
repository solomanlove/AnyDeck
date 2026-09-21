import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/device_capture_compatibility.dart';
import '../../../core/scrcpy/scrcpy_launch_options.dart';

/// 纯音频转发（无画面）状态模型
class AudioForwardState {
  /// 创建纯音频转发状态模型
  const AudioForwardState({
    this.isActive = false,
    this.isStarting = false,
    this.sessionId,
    this.errorMessage,
  });

  /// 是否正在转发音频
  final bool isActive;

  /// 是否正在启动过程中
  final bool isStarting;

  /// 当前运行的 scrcpy session ID
  final String? sessionId;

  /// 错误信息（如有）
  final String? errorMessage;

  /// 复制并更新部分属性
  AudioForwardState copyWith({
    bool? isActive,
    bool? isStarting,
    String? sessionId,
    String? errorMessage,
    bool clearSessionId = false,
    bool clearError = false,
  }) {
    return AudioForwardState(
      isActive: isActive ?? this.isActive,
      isStarting: isStarting ?? this.isStarting,
      sessionId: clearSessionId ? null : (sessionId ?? this.sessionId),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// 针对单台设备纯音频转发的状态控制器 Provider (按 deviceId 隔离)
final audioForwardControllerProvider =
    NotifierProvider.family<AudioForwardController, AudioForwardState, String>(
      AudioForwardController.new,
    );

/// 纯音频转发业务控制器，负责管理 scrcpy 纯音频进程生命周期及异常状态回收。
class AudioForwardController extends Notifier<AudioForwardState> {
  /// 创建纯音频控制器实例，绑定目标设备 ID
  AudioForwardController(this.deviceId);

  /// 目标 ADB 设备 ID / 序列号
  final String deviceId;

  @override
  AudioForwardState build() {
    // 监听设备在线状态：如果设备离线且正在运行，则自动停止并回收资源
    ref.listen(deviceOnlineProvider(deviceId), (_, isOnline) {
      if (!isOnline && (state.isActive || state.sessionId != null)) {
        stop();
      }
    });

    // 页面/Provider 销毁时清理进程，防止僵尸进程
    ref.onDispose(() {
      final sessionId = state.sessionId;
      if (sessionId != null) {
        ref.read(scrcpyServiceProvider).stop(sessionId);
      }
    });

    return const AudioForwardState();
  }

  /// 启动纯音频转发（无画面）
  /// 返回是否启动成功
  Future<bool> start() async {
    if (state.isStarting || state.isActive) return false;

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
      final scrcpy = ref.read(scrcpyServiceProvider);

      // 若设备处于休眠或息屏状态，发送唤醒键确保音频系统正常产出
      unawaited(adb.shellArgs(deviceId, ['input', 'keyevent', '224']));

      // 启动纯音频 scrcpy 实例
      final session = await scrcpy.start(
        deviceId: deviceId,
        options: const ScrcpyLaunchOptions(
          noVideo: true,
          requireAudio: true,
        ),
        adbPath: adb.executable,
        onExit: (exitCode) {
          if (ref.mounted && state.sessionId != null) {
            state = const AudioForwardState();
          }
        },
      );

      state = state.copyWith(
        isActive: true,
        isStarting: false,
        sessionId: session.id,
      );
      return true;
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(
          isActive: false,
          isStarting: false,
          clearSessionId: true,
          errorMessage: e.toString(),
        );
      }
      return false;
    }
  }

  /// 停止纯音频转发
  Future<void> stop() async {
    final sessionId = state.sessionId;
    state = const AudioForwardState();
    if (sessionId != null) {
      await ref.read(scrcpyServiceProvider).stop(sessionId);
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
